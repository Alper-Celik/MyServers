# Restart recovery for the fleet's own services.
#
# Units are named per host (<host>/restart-recovery.nix): a module cannot map
# over config.systemd.services without recursing — the option's key set is
# needed to build the definition that produces it. Retries stay bounded so a
# genuinely broken unit still reaches the `failed` state the fleet alert rule
# watches, instead of flapping below the start-rate limit forever.
#
# Why not a systemd-level default: system.conf has no `DefaultRestart=` (only
# `DefaultRestartSec=` and the `DefaultStartLimit*` options), and a type drop-in
# (`/etc/systemd/system/service.d/`) OVERRIDES a unit's own Restart= rather than
# defaulting under it (checked against systemd 260). mkDefault is the only
# default semantics actually available, so the units stay named.
{
  config,
  lib,
  ...
}:
let
  cfg = config.restartRecovery;

  # The ".service" form is accepted so a name from `systemctl` can be pasted
  # straight in; as a systemd.services key it would define a second, empty unit.
  units = map (unit: lib.removeSuffix ".service" unit) cfg.units;

  # One-shot boot jobs nixpkgs declares Type=simple, so the Type filter in
  # `uncovered` cannot see them; they need no recovery.
  bootJobs = [
    "mandb"
    "reload-systemd-vconsole-setup"
  ];

  # Drift tripwire: a daemon a host should be running but that has no Restart=.
  uncovered = lib.filter (
    name:
    let
      unit = config.systemd.services.${name};
    in
    unit.enable
    && !(lib.elem name units)
    && !(lib.elem name bootJobs)
    && (unit.serviceConfig.Restart or null) == null
    # oneshot boot steps re-run at the next boot or timer tick, and surface in
    # the failed-state alert either way — only daemons belong in the lists.
    && !(lib.any (type: type == "oneshot") (lib.toList (unit.serviceConfig.Type or "simple")))
    && !(lib.hasPrefix "systemd-" name)
    && !(lib.hasPrefix "dbus" name)
    && !(lib.hasInfix "@" name)
    &&
      (lib.intersectLists unit.wantedBy [
        "multi-user.target"
        "bluetooth.target"
        "samba.target"
      ]) != [ ]
  ) (lib.attrNames config.systemd.services);
in
{
  options.restartRecovery = {
    units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "redis-audiomuse" ];
      description = ''
        Services that should come back on their own after a failed start,
        named by their `systemd.services` key.
      '';
    };

    restart = lib.mkOption {
      type = lib.types.str;
      default = "on-failure";
      description = "Restart= to default onto the listed units.";
    };

    restartSec = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Delay before each restart attempt, in seconds.";
    };

    startLimitIntervalSec = lib.mkOption {
      type = lib.types.int;
      default = 120;
      description = "Window for the start rate limit, in seconds.";
    };

    startLimitBurst = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = ''
        Restart attempts allowed within startLimitIntervalSec before the unit
        is left failed.
      '';
    };
  };

  config = {
    warnings = lib.optional (uncovered != [ ]) ''
      restart-recovery: ${toString (lib.length uncovered)} service(s) lack restart recovery:
      ${lib.concatStringsSep ", " uncovered}
      Add them to restartRecovery.units in this host's restart-recovery.nix.
    '';

    systemd.services = lib.mkIf (units != [ ]) (
      lib.genAttrs units (name: {
        serviceConfig = {
          Restart = lib.mkDefault cfg.restart;
          RestartSec = lib.mkDefault cfg.restartSec;
        };
        startLimitIntervalSec = lib.mkDefault cfg.startLimitIntervalSec;
        startLimitBurst = lib.mkDefault cfg.startLimitBurst;
      })
    );
  };
}
