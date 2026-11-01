{ pkgs, ... }:
let
  check = pkgs.writeShellApplication {
    name = "reboot-stale-kernel";
    runtimeInputs = with pkgs; [
      coreutils
      procps
      systemd
    ];
    text = ''
      # Compare resolved kernel store paths, not version strings: the rpi kernel
      # version carries an -unstable_<date> suffix that would poison an uname check.
      if [ ! -e /run/current-system/kernel ] || [ ! -e /run/booted-system/kernel ]; then
        echo "kernel symlinks missing, skipping"
        exit 0
      fi
      current="$(readlink -f /run/current-system/kernel)"
      booted="$(readlink -f /run/booted-system/kernel)"
      if [ "$current" = "$booted" ]; then
        exit 0
      fi
      # Rebooting mid-activation strands the host holding the switch lock.
      if pgrep -f switch-to-configuration >/dev/null; then
        echo "activation in progress, skipping"
        exit 0
      fi
      echo "booted kernel $booted differs from current generation kernel $current, rebooting"
      systemctl reboot
    '';
  };
in
{
  systemd.services.reboot-stale-kernel = {
    description = "Reboot when the running kernel differs from the current generation";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${check}/bin/reboot-stale-kernel";
    };
  };

  systemd.timers.reboot-stale-kernel = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 00:15:00";
      RandomizedDelaySec = "20min";
      Persistent = true;
    };
  };
}
