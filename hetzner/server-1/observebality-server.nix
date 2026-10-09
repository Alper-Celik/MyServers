{
  config,
  ...
}:
let
  grafana-domain = "observe.lab.alper-celik.dev";
  mimir-domain = "mimir.lab.alper-celik.dev";
  loki-domain = "loki.lab.alper-celik.dev";
  tempo-domain = "tempo.lab.alper-celik.dev";
  tempo-otlp-domain = "tempo-otlp.lab.alper-celik.dev";
  pyroscope-domain = "pyroscope.lab.alper-celik.dev";
  mimir-version = config.services.mimir.package.version;
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
        {
          name = "Tempo";
          type = "tempo";
          uid = "tempo";
          url = "https://${tempo-domain}";
        }
        {
          name = "Pyroscope";
          type = "phlare";
          uid = "pyroscope";
          url = "https://${pyroscope-domain}";
        }
      ];
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

  # tempo (trace database)
  services.caddy.virtualHosts.${tempo-domain} = {
    extraConfig = "reverse_proxy http://127.0.0.1:${toString config.services.tempo.settings.server.http_listen_port}";
  };

  # OTLP ingest for hosts without a local Tempo (alloy exporters on rpi5/ovhcloud)
  services.caddy.virtualHosts.${tempo-otlp-domain} = {
    extraConfig = "reverse_proxy http://${config.services.tempo.settings.distributor.receivers.otlp.protocols.http.endpoint}";
  };

  systemd.services.tempo.serviceConfig.EnvironmentFile = config.sops.secrets.TEMPO_S3_ENV_FILE.path;
  services.tempo = {
    enable = true;
    extraFlags = [ "--config.expand-env=true" ];
    settings = {
      stream_over_http_enabled = true;
      server = {
        # rings advertise the interface IP, so the server must accept on all
        # interfaces; the firewall keeps the ports local (no allowedTCPPorts)
        http_listen_port = 3200;
        # mimir's grpc defaults to 9095, loki took 9096
        grpc_listen_port = 9097;
        log_level = "warn";
      };

      # OTLP receivers on shifted ports: this host's Alloy already occupies
      # 4317/4318, so Alloy exports traces here instead.
      distributor.receivers.otlp.protocols = {
        grpc.endpoint = "127.0.0.1:14317";
        http.endpoint = "127.0.0.1:14318";
      };

      # mimir's memberlist owns 7946 on this host
      memberlist = {
        bind_addr = [ "127.0.0.1" ];
        bind_port = 7947;
      };

      compactor.compaction.block_retention = "0"; # infinite consider tuning it if storage costs get out of control

      storage.trace = {
        backend = "s3";
        s3 = {
          endpoint = "s3.eu-central-003.backblazeb2.com";
          region = "eu-central-003";
          bucket = "tempo-alper";
          access_key = "$\{S3_ACCESS_KEY_ID\}";
          secret_key = "$\{S3_SECRET_ACCESS_KEY\}";
        };
        wal.path = "/var/lib/tempo/wal";
      };

      usage_report.reporting_enabled = false;
    };
  };

  # pyroscope (continuous profiling)
  services.caddy.virtualHosts.${pyroscope-domain} = {
    extraConfig = "reverse_proxy http://127.0.0.1:${toString config.services.pyroscope.settings.server.http_listen_port}";
  };

  systemd.services.pyroscope.serviceConfig.EnvironmentFile =
    config.sops.secrets.PYROSCOPE_S3_ENV_FILE.path;
  services.pyroscope = {
    enable = true;
    extraFlags = [ "--config.expand-env=true" ];
    settings = {
      server = {
        # the module defaults to 127.0.0.1, but pyroscope's rings advertise the
        # interface IP — bind all and let the firewall keep the ports local
        http_listen_address = "0.0.0.0";
        grpc_listen_address = "0.0.0.0";
        # mimir's grpc defaults to 9095, loki took 9096, tempo 9097
        grpc_listen_port = 9098;
      };

      storage = {
        backend = "s3";
        s3 = {
          bucket_name = "pyroscope-alper";
          endpoint = "s3.eu-central-003.backblazeb2.com";
          region = "eu-central-003";
          access_key_id = "$\{S3_ACCESS_KEY_ID\}";
          secret_access_key = "$\{S3_SECRET_ACCESS_KEY\}";
        };
      };

      pyroscopedb.data_path = "/var/lib/pyroscope";
      # mimir's memberlist owns 7946, tempo took 7947
      memberlist = {
        bind_addr = [ "127.0.0.1" ];
        bind_port = 7948;
      };
      analytics.reporting_enabled = false;
    };
  };
}
