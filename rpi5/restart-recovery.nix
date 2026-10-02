# Daemons whose failure leaves the box degraded until someone notices.
# Per-connection instances (@), socket/D-Bus/timer-activated units and oneshot
# boot steps are left out: systemd re-runs those anyway, or they surface in the
# failed-state alert as they always did.
{
  restartRecovery.units = [
    "NetworkManager"
    "NetworkManager-dispatcher"
    "avahi-daemon"
    "bluetooth"
    "mongodb"
    "navidrome"
    "nextcloud-cron"
    "nextcloud-update-db"
    "pgadmin"
    "qbittorrent"
    "redis-audiomuse"
    "redis-immich"
    "redis-nextcloud"
    "samba-nmbd"
    "samba-smbd"
    "samba-winbindd"
    "samba-wsdd"
    "tailscaled"
    "wpa_supplicant"
  ];
}
