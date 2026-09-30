# Hindsight long-term memory for the Hermes agent: the provider plugin from the
# `hindsight` flake input, against the self-hosted server on ovhcloud-server-1.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  hindsightSrc = inputs.hindsight;

  # The hermes-agent package builds against its OWN nixpkgs input (MyServers
  # does not make it follow the root), and the module only puts a package on
  # PYTHONPATH if its `pythonModule` is that build's exact interpreter. Build
  # the bundle with the root pkgs instead and it is dropped silently.
  hermesPkgs = inputs.hermes-agent.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  clientVersion =
    (lib.importTOML "${hindsightSrc}/hindsight-clients/python/pyproject.toml").project.version;

  sitePackages = hermesPkgs.python312.sitePackages;

  # Built with hatchling: the plugin reads
  # importlib.metadata.version("hindsight-client"), and without the wheel's
  # dist-info it warns and retries a lazy install that a nix install refuses,
  # every session start. `dependencies` is empty and the runtime-dep check off
  # because the client's deps already ride the hermes venv — declaring them
  # here trips the module's checkPackageCollisions.
  hindsightClient = hermesPkgs.python312Packages.buildPythonPackage {
    pname = "hindsight-client";
    version = clientVersion;
    pyproject = true;
    src = "${hindsightSrc}/hindsight-clients/python";
    build-system = [ hermesPkgs.python312Packages.hatchling ];
    dependencies = [ ];
    doCheck = false;
    dontCheckRuntimeDeps = true;
  };

  # What lands on PYTHONPATH: the client plus aiohttp-retry, the one dependency
  # the venv lacks (imported by the generated hindsight_client_api/rest.py).
  hindsightPython = hermesPkgs.python312Packages.toPythonModule (
    hermesPkgs.runCommand "hermes-hindsight-python" { } ''
      mkdir -p $out/${sitePackages}
      cp -r ${hindsightClient}/${sitePackages}/. $out/${sitePackages}/
      cp -r ${hermesPkgs.python312Packages.aiohttp-retry}/${sitePackages}/. $out/${sitePackages}/
    ''
  );

  hindsightPluginDir = "${hindsightSrc}/hindsight-integrations/hermes";

  hermesHome = "${config.services.hermes-agent.stateDir}/.hermes";
in
{
  services.hermes-agent = {
    extraPythonPackages = [ hindsightPython ];

    # Memory providers are kind "exclusive": Hermes' plugin gate skips them, so
    # one is selected here and not in plugins.enabled.
    settings.memory.provider = "hindsight";

    # Read from $HERMES_HOME/hindsight/config.json, which outranks the
    # HINDSIGHT_* environment variables.
    hermesHomeFiles."hindsight/config.json" = builtins.toJSON {
      # The server already runs on ovhcloud-server-1. Straight to its published
      # port over the tailnet: WireGuard-encrypted, and skipping caddy means no
      # internal CA to trust.
      mode = "local_external";
      api_url = "http://ovhcloud-server-1.tailnet.alper-celik.dev:21912";
      # Own bank, so the other client on this server (omp) never writes here.
      bank_id = "alper_hermes";
      # Status lines off: nothing here is worth a message per recall/retain.
      recall_indicator = false;
      retain_indicator = false;
    };
  };

  # The provider is found BY DIRECTORY NAME (plugins/<memory.provider>), so this
  # link cannot be one of extraPlugins' nix-managed-<name> links; activation
  # only prunes those, leaving this one alone.
  systemd.tmpfiles.rules = [
    "d ${hermesHome}/hindsight 2770 ${config.services.hermes-agent.user} ${config.services.hermes-agent.group} - -"
    "L+ ${hermesHome}/plugins/hindsight - - - - ${hindsightPluginDir}"
  ];
}
