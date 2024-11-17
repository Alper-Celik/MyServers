{ config, ... }:
{
  users = {
    groups.samba-guest = { };
    users.samba-guest = {
      group = "samba-guest";
      isNormalUser = true;
    };
  };

  services.samba = {
    enable = true;
    openFirewall = true;

    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "network-drive(yedeksiz)";
        "netbios name" = "celik-samba";
        "security" = "user";
        "guest account" = "samba-guest";
        "map to guest" = "bad user";
        "hosts allow" = "192.168.0.0/16 127.0.0.1 localhost 100.64.0.0/10";
        "hosts deny" = "0.0.0.0/0";
      };

      public = {

        "server min protocol" = "NT1";
        "read only" = "no";
        browseable = "yes";
        comment = "Public samba share.";
        "writable" = "yes";
        "guest ok" = "yes";
        path = "/export/network-drive";
        "create mask" = "0775";
        "directory mask" = "0755";

        "force user" = "samba-guest";

      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  services.avahi = {
    publish.enable = true;
    publish.userServices = true;
    # ^^ Needed to allow samba to automatically register mDNS records (without the need for an `extraServiceFile`
    nssmdns4 = true;
    # ^^ Not one hundred percent sure if this is needed- if it aint broke, don't fix it
    enable = true;
    openFirewall = true;
  };

  networking.firewall.enable = true;
  networking.firewall.allowPing = true;

}
