{
  config,
  ...
}:
let
  grafana-domain = "observe.lab.alper-celik.dev";
  mimir-domain = "mimir.lab.alper-celik.dev";
  loki-domain = "loki.lab.alper-celik.dev";
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
          };
        }
        {
          name = "Loki";
          type = "loki";
          uid = "loki";
          url = "https://${loki-domain}";
        }
      ];
    };

  };

  services.nginx.virtualHosts.${grafana-domain} = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;
    locations."/" = {
      proxyPass = "http://${toString config.services.grafana.settings.server.http_addr}:${toString config.services.grafana.settings.server.http_port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  # mimir (time series database)

  services.nginx.virtualHosts.${mimir-domain} = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;
    locations."/" = {
      proxyPass = "http://[::1]:${toString config.services.mimir.configuration.server.http_listen_port}";
      extraConfig = ''
        proxy_set_header X-Scope-OrgID anonymous;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        client_max_body_size 512m;
      '';
    };
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
  services.nginx.virtualHosts.${loki-domain} = {
    forceSSL = true;
    enableACME = true;
    acmeRoot = null;
    locations."/" = {
      proxyPass = "http://[::1]:${toString config.services.mimir.configuration.server.http_listen_port}";
      extraConfig = ''
        proxy_set_header X-Scope-OrgID anonymous;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        client_max_body_size 512m;
      '';
    };
  };
  systemd.services.loki.serviceConfig.EnvironmentFile = config.sops.secrets.LOKI_S3_ENV_FILE.path;
  services.loki = {
    enable = true;
    extraFlags = [ "-config.expand-env=true" ];
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
      limits_config.retention_period = 0; # infinite consider tuning it if storage costs get out of control

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
        access_key_id = "$S3_ACCESS_KEY_ID";
        secret_access_key = "$S3_SECRET_ACCESS_KEY";
        bucketnames = "loki-alper";
      };
    };
  };
}
