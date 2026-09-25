{
  config,
  ...
}:
let
  grafana-domain = "observe.lab.alper-celik.dev";
  mimir-domain = "mimir.lab.alper-celik.dev";
  loki-domain = "loki.lab.alper-celik.dev";
  mimir-version = config.services.mimir.package.version;

  # Units whose absence from the "active" state is a real outage. Each exists
  # on at least one host; hosts that don't run a unit have no series at all,
  # so they never trip the rule.
  critical-units = "sshd\\.service|tailscaled\\.service|alloy\\.service|caddy\\.service|grafana\\.service|mimir\\.service|loki\\.service|postgresql\\.service|hermes-agent\\.service";

  # A Grafana-managed alert rule = instant PromQL query (A) + threshold
  # expression (B). NoData stays OK everywhere here: an empty result is the
  # healthy case ("nothing failed", "no unreachable target"), so only a real
  # value of 1 may fire.
  mkAlertData = expr: [
    {
      refId = "A";
      datasourceUid = "mimir";
      relativeTimeRange = {
        from = 300;
        to = 0;
      };
      model = {
        editorMode = "code";
        expr = expr;
        instant = true;
        range = false;
        intervalMs = 1000;
        maxDataPoints = 43200;
        refId = "A";
      };
    }
    {
      refId = "B";
      datasourceUid = "__expr__";
      relativeTimeRange = {
        from = 300;
        to = 0;
      };
      model = {
        refId = "B";
        type = "threshold";
        expression = "A";
        intervalMs = 1000;
        maxDataPoints = 43200;
        datasource = {
          type = "__expr__";
          uid = "__expr__";
        };
        conditions = [
          {
            type = "query";
            query.params = [ "A" ];
            reducer = {
              type = "last";
              params = [ ];
            };
            evaluator = {
              type = "gt";
              params = [ 0 ];
            };
            operator.type = "and";
          }
        ];
      };
    }
  ];
in
{
  # grafana (data dashboard)
  services.postgresql = {
    enable = true;
    ensureDatabases = [ "grafana" ];
    ensureUsers = [
      {
        name = "grafana";
        ensureDBOwnership = true;
      }
    ];
  };
  services.grafana = {
    enable = true;
    settings = {
      security.secret_key = "SW2YcwTIb9zpOOhoPsMm"; # TODO: Please lets not keep it ok 🥹
      server = {
        http_addr = "127.0.0.1";
        http_port = 3080;
        enforce_domain = true;
        enable_gzip = true;
        domain = grafana-domain;
      };
      database = {
        type = "postgres";
        host = "/run/postgresql";
        user = "grafana";
      };
    };
    provision = {
      enable = true;

      datasources.settings.datasources = [
        {
          name = "Mimir";
          type = "prometheus";
          uid = "mimir";
          url = "https://${mimir-domain}/prometheus";
          jsonData = {
            httpMethod = "POST";
            prometheusType = "Mimir";
            prometheusVersion = mimir-version;
          };
        }
        {
          name = "Loki";
          type = "loki";
          uid = "loki";
          url = "https://${loki-domain}";
        }
      ];

      # Alert rules, file-provisioned (provisioning/alerting/rules.yaml).
      # The folder is created by the alert provisioner on first start; routing
      # uses the existing notification policy (Telegram). Rules are NOT
      # editable in the UI — change them here and redeploy.
      alerting.rules.settings = {
        apiVersion = 1;
        groups = [
          {
            orgId = 1;
            name = "fleet-availability";
            folder = "Fleet Alerts";
            interval = "60s";
            rules = [
              # Any unit that systemd has put in the failed state.
              {
                uid = "fleet-systemd-unit-failed";
                title = "Systemd unit failed";
                condition = "B";
                for = "5m";
                noDataState = "OK";
                execErrState = "Alerting";
                labels = {
                  severity = "warning";
                  category = "systemd";
                };
                annotations = {
                  summary = "systemd unit {{ $labels.name }} is failed on {{ $labels.host }}";
                  description = "node_systemd_unit_state{state=\"failed\"} == 1 for 5m — {{ $labels.name }} ({{ $labels.type }}) on {{ $labels.host }}.";
                };
                data = mkAlertData ''node_systemd_unit_state{state="failed"} == 1'';
              }
              # A unit that matters (ssh, tailscale, alloy, caddy, grafana,
              # mimir, loki, postgres, hermes) leaving the active state: stopped,
              # failed or stuck deactivating.
              {
                uid = "fleet-systemd-critical-unit-down";
                title = "Critical systemd unit not active";
                condition = "B";
                for = "5m";
                noDataState = "OK";
                execErrState = "Alerting";
                labels = {
                  severity = "critical";
                  category = "systemd";
                };
                annotations = {
                  summary = "critical unit {{ $labels.name }} is not active on {{ $labels.host }}";
                  description = "max_over_time(node_systemd_unit_state{state=\"active\", name=~\"${critical-units}\"}[10m]) == 0 for 5m — {{ $labels.name }} on {{ $labels.host }} is stopped or failed.";
                };
                data = mkAlertData "max_over_time(node_systemd_unit_state{state=\"active\", name=~\"${critical-units}\"}[10m]) == 0";
              }
              # Anything the fleet scrapes that has been unreachable for 10m
              # (remote scrapes like the openwrt router, node_exporter jobs, …).
              {
                uid = "fleet-scrape-target-down";
                title = "Scrape target down";
                condition = "B";
                for = "10m";
                noDataState = "OK";
                execErrState = "Alerting";
                labels = {
                  severity = "critical";
                  category = "scrape";
                };
                annotations = {
                  summary = "scrape target {{ $labels.instance }} (job {{ $labels.job }}) is down";
                  description = "up == 0 for 10m — {{ $labels.job }} cannot reach {{ $labels.instance }} (host {{ $labels.host }}).";
                };
                data = mkAlertData "up == 0";
              }
              # Whole-host downtime: hosts push their own node_exporter/alloy
              # metrics, so a dead machine makes the series disappear instead of
              # turning 0 — nothing new is pushed to alert on. Compare the
              # series against itself 20m ago to catch the disappearance.
              {
                uid = "fleet-host-metrics-missing";
                title = "Host stopped reporting";
                condition = "B";
                for = "5m";
                noDataState = "OK";
                execErrState = "Alerting";
                labels = {
                  severity = "critical";
                  category = "host";
                };
                annotations = {
                  summary = "{{ $labels.host }} stopped pushing metrics";
                  description = "up{job=\"integrations/unix\"} had samples 20m ago and has none now: the host is down or its node_exporter/alloy died.";
                };
                data = mkAlertData ''up{job="integrations/unix"} offset 20m unless up{job="integrations/unix"}'';
              }
            ];
          }
        ];
      };
    };

  };

  services.caddy.virtualHosts.${grafana-domain} = {
    extraConfig = "reverse_proxy http://${toString config.services.grafana.settings.server.http_addr}:${toString config.services.grafana.settings.server.http_port}";
  };

  # mimir (time series database)

  services.caddy.virtualHosts.${mimir-domain} = {
    extraConfig = ''
      header {
        X-Scope-OrgID anonymous
      }
      reverse_proxy http://[::1]:${toString config.services.mimir.configuration.server.http_listen_port}
    '';
  };

  systemd.services.mimir.serviceConfig.EnvironmentFile = config.sops.secrets.MIMIR_S3_ENV_FILE.path;
  services.mimir = {
    enable = true;
    extraFlags = [ "--config.expand-env=true" ];
    configuration = {
      target = "all";
      multitenancy_enabled = false;

      server = {
        http_listen_port = 9009;
        log_level = "warn";
      };

      common.storage = {

        backend = "s3";
        s3 = {
          endpoint = "s3.eu-central-003.backblazeb2.com";
          region = "eu-central-003";
          access_key_id = "$S3_ACCESS_KEY_ID";
          secret_access_key = "$S3_SECRET_ACCESS_KEY";
        };
      };

      blocks_storage = {
        s3.bucket_name = "mimir-blocks-alper";
        bucket_store = {
          sync_dir = "/var/lib/mimir/tsdb-sync";
          index_cache = {
            backend = "inmemory";
            inmemory.max_size_bytes = 512 * 1024 * 1024;
          };
        };
        tsdb.dir = "/var/lib/mimir/tsdb";
      };
      alertmanager_storage.s3.bucket_name = "mimir-alertmanager-alper";

      ruler_storage.s3.bucket_name = "mimir-ruler-alper";

      memberlist.join_members = [ "127.0.0.1" ];

      compactor = {
        data_dir = "/var/lib/mimir/compactor";
        sharding_ring.kvstore.store = "memberlist";

      };
      # Single node ring config
      ingester.ring = {
        instance_addr = "127.0.0.1";
        kvstore.store = "memberlist";
        replication_factor = 1;
      };
      distributor.ring = {
        instance_addr = "127.0.0.1";
        kvstore.store = "memberlist";
      };

      store_gateway.sharding_ring.replication_factor = 1;

      limits = {
        out_of_order_time_window = "168h"; # a week of playback just in case my local network goes out for a week
        compactor_blocks_retention_period = 0; # infinite consider tuning it if storage costs get out of control
      };
    };
  };

  # loki (log database)
  services.caddy.virtualHosts.${loki-domain} = {
    extraConfig = ''
      header {
        X-Scope-OrgID anonymous
      }
      reverse_proxy http://[::1]:${toString config.services.loki.configuration.server.http_listen_port}
    '';
  };
  systemd.services.loki.serviceConfig.EnvironmentFile = config.sops.secrets.LOKI_S3_ENV_FILE.path;
  services.loki = {
    enable = true;
    extraFlags = [ "--config.expand-env=true" ];
    configuration = {
      auth_enabled = false;
      server = {
        http_listen_port = 3100;
        grpc_listen_port = 9096;
        log_level = "warn";
      };

      common = {
        instance_addr = "127.0.0.1";
        path_prefix = "/var/lib/loki";
        replication_factor = 1;
        ring.kvstore.store = "inmemory";
      };
      limits_config = {
        retention_period = 0; # infinite consider tuning it if storage costs get out of control
        ingestion_rate_mb = 50;
      };

      compactor = {
        working_directory = "/var/lib/loki/compactor";
        delete_request_store = "s3";
        retention_enabled = true;
      };
      schema_config = {
        configs = [
          {
            from = "2025-01-01";
            store = "tsdb";
            object_store = "s3";
            schema = "v13";
            index = {
              prefix = "loki_index_";
              period = "24h";
            };
          }
        ];
      };
      storage_config.aws = {
        endpoint = "s3.eu-central-003.backblazeb2.com";
        region = "eu-central-003";
        access_key_id = "$\{S3_ACCESS_KEY_ID\}";
        secret_access_key = "$\{S3_SECRET_ACCESS_KEY\}";
        bucketnames = "loki-alper";
      };
    };
  };
}
