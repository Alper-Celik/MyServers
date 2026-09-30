# Hindsight long-term memory for the Hermes agent: the provider plugin from the
# `hindsight` flake input, against the server on ovhcloud-server-1.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  hindsightSrc = inputs.hindsight;

  # The hermes-agent package builds against its OWN nixpkgs input (MyServers does
  # not make it follow the root), and the module only puts a package on PYTHONPATH
  # if its `pythonModule` is that build's exact interpreter: a bundle built with
  # the root pkgs is dropped silently.
  hermesPkgs = inputs.hermes-agent.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  clientVersion =
    (lib.importTOML "${hindsightSrc}/hindsight-clients/python/pyproject.toml").project.version;

  sitePackages = hermesPkgs.python312.sitePackages;

  # A wheel, not a plain copy: the plugin reads
  # importlib.metadata.version("hindsight-client") and falls back to a lazy install
  # when the dist-info is missing. `dependencies` stays empty and the runtime-dep
  # check off because those deps ride the hermes venv already, and declaring them
  # trips the module's checkPackageCollisions.
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

  # The client, plus aiohttp-retry — the one dependency the venv lacks (imported
  # by the generated hindsight_client_api/rest.py).
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

    # Memory providers are kind "exclusive": the plugin gate skips them, so the
    # selection is here and not in plugins.enabled.
    settings.memory.provider = "hindsight";

    # $HERMES_HOME/hindsight/config.json outranks the HINDSIGHT_* environment
    # variables. Unset keys keep the provider's defaults (bank "hermes").
    hermesHomeFiles."hindsight/config.json" = builtins.toJSON {
      mode = "local_external";
      api_url = "https://api.hindsight.lab.alper-celik.dev";
    };
  };

  # This link cannot be one of extraPlugins' `nix-managed-<name>` ones: a memory
  # provider resolves by DIRECTORY name (`plugins/<memory.provider>`), so the
  # prefix would leave `memory.provider = "hindsight"` unresolvable.
  systemd.tmpfiles.rules = [
    "d ${hermesHome}/hindsight 2770 ${config.services.hermes-agent.user} ${config.services.hermes-agent.group} - -"
    "L+ ${hermesHome}/plugins/hindsight - - - - ${hindsightPluginDir}"
  ];
}
