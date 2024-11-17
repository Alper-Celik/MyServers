{ ... }:
{
  defaultTTL = 300;
  zones."alper-celik.dev" =
    let
      rpi5 = "rpi5.devices.alper-celik.dev";
      rpi5-tailnet = "rpi5.tailnet.alper-celik.dev";
      github = "alper-celik.github.io";
    in
    {
      # devices
      "do-vm".a.data = "146.190.206.52";
      # "rpi5.devices".a = {
      #   data = "85.109.15.96";
      #   ttl = 60;
      # };
      "rpi5.tailnet".a.data = "100.104.52.23";

      # services TODO: move these to nixos config ?
      "bitwarden.lab".cname.data = rpi5-tailnet;
      "freshrss.lab".cname.data = rpi5-tailnet;
      "nextcloud.lab".cname.data = rpi5-tailnet;
      "pgadmin.lab".cname.data = rpi5-tailnet;
      "collabora-online.lab".cname.data = rpi5-tailnet;
      "id.lab".cname.data = rpi5-tailnet;
      "home.lab".cname.data = rpi5-tailnet;
      "jellyfin.lab".cname.data = rpi5-tailnet;

      "beta.ym-pdf".cname.data = rpi5;

      "modded-mc".cname.data = "do-vm.alper-celik.dev";

      # github pages
      "blog".cname.data = github;
      "ym-pdf".cname.data = github;

      # mail and such
      # "5xwxv5wqu77m".cname.data = "gv-56dcrarorpfoh5.dv.googlehosted.com";
      # "".mx = {
      #   data = [
      #     {
      #       preference = 10;
      #       exchange = "mxb.mailgun.org";
      #     }
      #     {
      #       preference = 10;
      #       exchange = "mxa.mailgun.org";
      #     }
      #   ];
      #   ttl = 14352;
      # };
      # "".txt = {
      #   data = "v=spf1 include:mailgun.org ~all";
      #   ttl = 14352;
      # };
      # "mx._domainkey".txt = {
      #   data = "k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDLquF7Q4jCNfQKJ+wUU1fv5hgeZOEvEJ0HXkEdu1XrzXm20ECnKP2wwmJyEYP19uQ2rwx5KTVHCTIJAJWDMbi3UZC1VcZsi3U2HL8VVpsV8Q/LfulrprqTbEc/KxwwgPWayW3/lH1mP2Bh74qtHXl4CR1X\" \"7UG2chBocCHpsT76swIDAQAB";
      #   ttl = 14400;
      # };

    };
}
