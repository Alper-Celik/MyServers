{ config, ... }:
{
  services.ddclient = {
    enable = true;
    protocol = "cloudflare";
    zone = "alper-celik.dev";
    username = "dev.alpercelik@gmail.com";
    passwordFile = config.sops.secrets.CLOUDFLARE_API_KEY.path;
    domains = [ "rpi5.devices.alper-celik.dev" ];

    usev4 = "webv4,webv4=ipify-ipv4";
    usev6 = "";
  };
}
