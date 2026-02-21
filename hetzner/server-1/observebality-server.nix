{
  config,
  ...
}:
let
  grafana-domain = "observe.lab.alper-celik.dev";
in
{

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

      limits.out_of_order_time_window = "168h"; # a week of playback just in case my local network goes out for a week
    };
  };

}
