# SPDX-FileCopyrightText: 2026 Alper Çelik <alper@alper-celik.dev>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Loki carries the full journal and the caddy access logs (grafana-alloy tails
# both), so local copies only need crash-recent history. This host is the one
# that ran /var out of space under the defaults.
{
  # enable back after everything is >= 26.11
  # services.journald.settings.Journal = {
  #   SystemMaxUse = "1G";
  #   MaxRetentionSec = "3day";
  # };

  systemd.tmpfiles.rules = [
    # caddy rotates its access logs by size but never prunes; the daily
    # systemd-tmpfiles-clean.timer applies the age. "m:" pins the age check to
    # mtime only: the default also consults atime/ctime/btime, so any read
    # (backups, scanners) keeps a rotated log alive forever.
    "e /var/log/caddy - - - m:3d"
  ];
}
