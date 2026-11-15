# SecretSpec (https://secretspec.dev) env-file rendering.
#
# Declares secrets in a committed plaintext manifest; values are resolved at
# unit start by the `secretspec` CLI from a provider backend and written to a
# runtime env file the consumer unit reads via EnvironmentFile. Provider
# choice is host-level (`secretspec.defaultProvider` + `secretspec.providers`
# aliases, rendered into a user config every render unit reads); a render can
# still pin its own provider, and the manifest carries only declarations.
#
# Consumers wire it up by convention (name N):
#   unit       secretspec-render-N.service   (requires + after from consumer)
#   env file   /run/secretspec-N/env         (consumer's environmentFiles)
# The render unit re-runs at activation whenever sopsFile/manifest change; a
# consumer wanting restarts on secret rotation sets its own restartTriggers on
# the same sopsFile (and on config.secretspec.configDir when a provider swap
# could change values).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.secretspec;

  # The user-level secretspec config the render units run against: the
  # default provider plus the alias table shared by every render on the
  # host. This is the knob that moves a provider swap out of the per-service
  # manifests — flip an alias URI or defaultProvider here once and every
  # render that names no chain of its own resolves through the new store.
  # Per-render `provider` still wins (--provider outranks everything but a
  # per-secret chain).
  configToml =
    let
      aliasLines = lib.mapAttrsToList (
        name: v:
        if lib.isString v then
          "${name} = ${builtins.toJSON v}"
        else if v.ref == null then
          "${name} = { uri = ${builtins.toJSON v.uri} }"
        else
          "${name} = { uri = ${builtins.toJSON v.uri}, ref = ${builtins.toJSON v.ref} }"
      ) cfg.providers;
      defaultLines = lib.optionals (cfg.defaultProvider != null) [
        "[defaults]"
        "provider = ${builtins.toJSON cfg.defaultProvider}"
      ];
    in
    lib.concatStringsSep "\n" (
      defaultLines
      ++ lib.optionals (aliasLines != [ ]) (
        [
          ""
          "[defaults.providers]"
        ]
        ++ aliasLines
      )
    );

  providerAlias = types.submodule {
    options = {
      uri = mkOption {
        type = types.str;
        description = "Provider URI the alias resolves to.";
      };
      ref = mkOption {
        type = types.nullOr (types.attrsOf types.anything);
        default = null;
        description = "Optional provider-native ref template ({project}/{profile}/{key} placeholders expand).";
      };
    };
  };

  renderModule =
    { name, config, ... }:
    {
      options = {
        manifest = mkOption {
          type = types.str;
          description = ''
            secretspec.toml contents. Plaintext by design — declarations and
            key names only, never values. A `sops://` URI may point at an
            absolute store path (e.g. the MyServersSecrets input).
          '';
        };
        sopsFile = mkOption {
          type = types.path;
          description = "Encrypted sops file the manifest resolves from; also the activation restart trigger.";
        };
        profile = mkOption {
          type = types.str;
          default = "default";
        };
        provider = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Provider alias or URI passed as --provider; null defers to secretspec.defaultProvider or the manifest's own defaults.";
        };
        sopsKeyFile = mkOption {
          type = types.path;
          default = /var/lib/sops-nix/key.txt;
          description = "age identity handed to the sops child process (SOPS_AGE_KEY_FILE).";
        };

        path = mkOption {
          type = types.str;
          readOnly = true;
          description = "Rendered env file for the consumer's environmentFiles.";
        };
        service = mkOption {
          type = types.str;
          readOnly = true;
          description = "Render unit the consumer should require and order after.";
        };
      };

      config = {
        path = "/run/secretspec-${name}/env";
        service = "secretspec-render-${name}.service";
      };
    };
in
{
  options.secretspec = {
    render = mkOption {
      type = types.attrsOf (types.submodule renderModule);
      default = { };
      description = "Env files to render from secretspec manifests.";
    };

    defaultProvider = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Default provider (alias, provider name, or URI) written to the render
        units' secretspec user config. Manifests that name no provider chain
        resolve through it; the fleet's one-line global provider knob.
      '';
    };

    providers = mkOption {
      type = types.attrsOf (types.either types.str providerAlias);
      default = { };
      description = ''
        Global provider aliases ([defaults.providers] in the render units'
        secretspec user config), shared by every render on this host.
      '';
    };

    configDir = mkOption {
      type = types.package;
      readOnly = true;
      description = ''
        Store dir carrying the user config (config.toml under secretspec/),
        set as XDG_CONFIG_HOME in every render unit. Consumers restart on it
        when a provider swap can change secret values.
      '';
    };
  };

  config = {
    secretspec.configDir = pkgs.writeTextDir "secretspec/config.toml" configToml;

    # listToAttrs, not mapAttrs: a mapAttrs-produced set loses its keys when
    # merged into an attrsOf option under this Nix (2.34) — sops-nix's
    # mapAttrs' pattern is the proven shape here.
    systemd.services = lib.mkIf (cfg.render != { }) (
      lib.listToAttrs (
        lib.mapAttrsToList (
          name: r:
          let
            manifestFile = pkgs.writeText "secretspec-${name}.toml" r.manifest;
            renderScript = pkgs.writeShellApplication {
              name = "secretspec-render-${name}";
              runtimeInputs = [
                pkgs.secretspec
                pkgs.sops
                pkgs.coreutils
              ];
              text = ''
                umask 077
                dir="/run/secretspec-${name}"
                tmp=$(mktemp "$dir/.env.XXXXXX")
                export SOPS_AGE_KEY_FILE=${lib.escapeShellArg (toString r.sopsKeyFile)}
                secretspec export --file ${lib.escapeShellArg (toString manifestFile)} \
                  --profile ${lib.escapeShellArg r.profile} \
                  ${lib.optionalString (r.provider != null) "--provider ${lib.escapeShellArg r.provider}"} \
                  --format dotenv >"$tmp"
                mv "$tmp" "$dir/env"
              '';
            };
          in
          lib.nameValuePair "secretspec-render-${name}" {
            description = "Render the ${name} env file from its secretspec manifest";
            restartTriggers = [
              r.sopsFile
              manifestFile
            ];
            serviceConfig = {
              Type = "oneshot";
              RuntimeDirectory = "secretspec-${name}";
              ExecStart = lib.getExe renderScript;
            };
            environment = {
              HOME = "/root";
              # the global default provider + alias table (see configToml)
              XDG_CONFIG_HOME = cfg.configDir;
            };
          }
        ) cfg.render
      )
    );
  };
}
