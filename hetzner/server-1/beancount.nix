{
  pkgs,
  self-pkgs,
  ...
}:
let
  port = 8330;
  uid = 852;
  gid = 853;
  stateDir = "/var/lib/fava";
  seed = ../../beancount/seed;
in
{
  users.groups.fava.gid = gid;
  users.users.fava = {
    uid = uid;
    isSystemUser = true;
    group = "fava";
    home = stateDir;
    createHome = true;
  };

  # Ledger, dashboard config and git history are host state: seeded from the
  # repo once, then owned by the service. The existence check keeps a later
  # deploy from clobbering a live ledger.
  systemd.services.fava-init = {
    before = [ "fava.service" ];
    requiredBy = [ "fava.service" ];
    path = [ pkgs.git ];
    serviceConfig = {
      Type = "oneshot";
      User = "fava";
      Group = "fava";
      StateDirectory = "fava";
      WorkingDirectory = stateDir;
      UMask = "0077";
    };
    script = ''
      set -eu
      # install -m, not cp: store copies are mode 0444 and the live ledger has to
      # stay writable, or the editor and auto_commit both fail.
      for f in main.beancount dashboards.jsx; do
        [ -e "$f" ] || install -m 0644 "${seed}/$f" "$f"
      done
      if [ ! -d .git ]; then
        git init -q -b main
        git config user.name fava
        git config user.email fava@hetzner-server-1
        git add -A
        git commit -q -m "seed ledger"
      fi
    '';
  };

  # git is on PATH for `fava.ext.auto_commit`, which commits the ledger after
  # every edit made through the web UI.
  systemd.services.fava = {
    description = "Fava — web interface for the beancount ledger";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = [ pkgs.git ];
    environment.HOME = stateDir;
    serviceConfig = {
      User = "fava";
      Group = "fava";
      WorkingDirectory = stateDir;
      ExecStart = "${self-pkgs.fava-env}/bin/fava --host 127.0.0.1 --port ${toString port} ${stateDir}/main.beancount";
      Restart = "on-failure";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ stateDir ];
    };
  };

  # No x-expose: common/caddy.nix keeps the tailnet-only client_ip guard.
  services.caddy.virtualHosts."fava.lab.alper-celik.dev" = {
    extraConfig = "reverse_proxy http://127.0.0.1:${toString port}";
  };
}
