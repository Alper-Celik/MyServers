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
  # not make it follow the root). The module (nix/hermes-agent.nix in the
  # hermes-agent flake) filters extraPythonPackages through
  # requiredPythonModules, which drops any package whose pythonModule is not the
  # interpreter of the sealed venv — silently. So the package set here must be
  # derived from what hermes actually builds with, not hardcoded: hardcoding
  # python312 is what broke hindsight when hermes moved to 3.14 — the
  # python312-built bundle kept building fine and then vanished from the
  # runtime PYTHONPATH (ModuleNotFoundError: hindsight_client). Derive the
  # family the same way hermes' own nix/pythonLock.nix does: the
  # major.minor of the packages.python.version pinned in its pm/lock.json
  # (the full version carries a patch and a build tag — e.g. "3.14.9+<date>" —
  # so it cannot name the pkgs attribute directly).
  hermesPkgs = inputs.hermes-agent.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  hermesPythonFamily =
    let
      version = (builtins.fromJSON (
        builtins.readFile "${inputs.hermes-agent}/pm/lock.json"
      )).packages.python.version;
      parts = builtins.match "([0-9]+)\\.([0-9]+)(\\..*)?" version;
    in
    builtins.elemAt parts 0 + "." + builtins.elemAt parts 1;
  hermesPythonPkgs = hermesPkgs."python${lib.replaceStrings [ "." ] [ "" ] hermesPythonFamily}Packages";

  clientVersion =
    (lib.importTOML "${hindsightSrc}/hindsight-clients/python/pyproject.toml").project.version;

  sitePackages = hermesPythonPkgs.python.sitePackages;

  # A wheel, not a plain copy: the plugin reads
  # importlib.metadata.version("hindsight-client") and falls back to a lazy install
  # when the dist-info is missing. Built FROM THE INPUT, not a PyPI pin: the
  # client then rides flake.lock bumps with the plugin it ships beside. The
  # plugin's floor check (`installed < 0.10.1`) still guards it.
  # `dependencies` stays empty and the runtime-dep
  # check off because those deps ride the hermes venv already, and declaring them
  # trips the module's checkPackageCollisions. That includes aiohttp-retry since
  # the hermes lock started shipping it — do not add it back to this bundle.
  hindsightClient = hermesPythonPkgs.buildPythonPackage {
    pname = "hindsight-client";
    version = clientVersion;
    pyproject = true;
    src = "${hindsightSrc}/hindsight-clients/python";
    build-system = [ hermesPythonPkgs.hatchling ];
    dependencies = [ ];
    doCheck = false;
    dontCheckRuntimeDeps = true;
  };

  hindsightPython = hermesPythonPkgs.toPythonModule (
    hermesPkgs.runCommand "hermes-hindsight-python" { } ''
      mkdir -p $out/${sitePackages}
      cp -r ${hindsightClient}/${sitePackages}/. $out/${sitePackages}/
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
    # variables.
    hermesHomeFiles."hindsight/config.json" = builtins.toJSON {
      mode = "local_external";
      api_url = "https://api.hindsight.lab.alper-celik.dev";
      bank_id = "default";
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
