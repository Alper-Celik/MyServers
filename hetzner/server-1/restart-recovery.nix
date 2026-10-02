# Daemons whose failure leaves the box degraded until someone notices.
# Per-connection instances (@), socket/D-Bus/timer-activated units and oneshot
# boot steps are left out: systemd re-runs those anyway, or they surface in the
# failed-state alert as they always did.
{
  restartRecovery.units = [
    "docker"
    "gitlab-runner"
    "ndppd"
    "tailscaled"
  ];
}
