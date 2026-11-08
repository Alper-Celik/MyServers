# SecretSpec (https://secretspec.dev) env-file rendering.
#
# Declares secrets in a committed plaintext manifest; values are resolved at
# unit start by the `secretspec` CLI from a provider backend and written to a
# runtime env file the consumer unit reads via EnvironmentFile. This module
# only renders — provider choice and fallback chains live in the manifest.
#
# Consumers wire it up by convention (name N):
#   unit       secretspec-render-N.service   (requires + after from consumer)
#   env file   /run/secretspec-N/env         (consumer's environmentFiles)
# The render unit re-runs at activation whenever sopsFile/manifest change; a
# consumer wanting restarts on secret rotation sets its own restartTriggers on
# the same sopsFile.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.secretspec;

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
          description = "Provider alias or URI (--provider); null lets the manifest default decide.";
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
  options.secretspec.render = mkOption {
    type = types.attrsOf (types.submodule renderModule);
    default = { };
    description = "Env files to render from secretspec manifests.";
  };

  config = lib.mkIf (cfg.render != { }) {
    # listToAttrs, not mapAttrs: a mapAttrs-produced set loses its keys when
    # merged into an attrsOf option under this Nix (2.34) — sops-nix's
    # mapAttrs' pattern is the proven shape here.
    systemd.services = lib.listToAttrs (
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
          environment.HOME = "/root";
        }
      ) cfg.render
    );
  };
}
