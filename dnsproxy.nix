{
  pkgs,
  lib,
  config,
  ...
}:
let
  routerLib = import ./tests/lib.nix { inherit lib; };

  bootstrapDNS = "8.8.8.8:53";
  primaryDNS = "10.13.93.50:53";
  secondaryDNS = "https://9.9.9.10/dns-query";
  listen = "-l 192.168.1.1 -l 10.13.84.1 -l 10.13.93.1 -l 10.13.83.1 -l 10.13.99.1 -l 10.13.86.1 -p 53";

  # Collect all entries from ip_manifest
  allEntries = builtins.concatLists (builtins.attrValues config.private.ip_manifest);
  namedEntries = builtins.filter (e: e.name != "") allEntries;

  # Find invalid DNS names
  invalidEntries = builtins.filter (e: !routerLib.isValidDnsName e.name) namedEntries;
  invalidNames = map (e: "${e.name} (${e.address})") invalidEntries;

  # Valid entries for hosts file
  validEntries = builtins.filter (e: routerLib.isValidDnsName e.name) namedEntries;

  # Publicly trusted LAN ingress names must resolve without consulting HA or a
  # WAN resolver. Keep these explicit so a missing target cannot be hidden by
  # dnsproxy's upstream fallback.
  lanIngressEntries = [
    {
      address = "75.2.60.5";
      name = "jjpdev.com";
    }
    {
      address = "10.13.84.100";
      name = "calibre.jjpdev.com";
    }
    {
      address = "10.13.84.100";
      name = "caddy.jjpdev.com";
    }
    {
      address = "10.13.93.50";
      name = "ha.jjpdev.com";
    }
    {
      address = "104.54.73.206";
      name = "home.jjpdev.com";
    }
    {
      address = "10.13.84.100";
      name = "nas.jjpdev.com";
    }
    {
      address = "10.54.0.88";
      name = "plex.jjpdev.com";
    }
    {
      address = "10.13.84.1";
      name = "router.jjpdev.com";
    }
    {
      address = "10.54.0.103";
      name = "vault.jjpdev.com";
    }
  ];

  # Generate hosts file content
  hostsFileContent =
    builtins.concatStringsSep "\n" (
      (map (e: "${e.address} ${e.name}.home") validEntries)
      ++ (map (e: "${e.address} ${e.name}") lanIngressEntries)
    )
    + "\n";
in
{
  config = {
    # Fail build if any names are invalid
    assertions = [
      {
        assertion = invalidEntries == [ ];
        message = "Invalid DNS names in ip_manifest: ${builtins.concatStringsSep ", " invalidNames}";
      }
    ];

    # Generate /etc/hosts.local from ip_manifest
    environment.etc."hosts.local".text = hostsFileContent;

    systemd.services.dnsproxy = {
      description = "DNS Proxy";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      restartTriggers = [ config.environment.etc."hosts.local".source ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.dnsproxy} --cache ${listen} -u ${primaryDNS} -f ${secondaryDNS} -b ${bootstrapDNS} --timeout=500ms --hosts-file-enabled --hosts-files=/etc/hosts.local";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      };
    };
  };
}
