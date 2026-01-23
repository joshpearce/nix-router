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

  # Generate hosts file content
  hostsFileContent =
    builtins.concatStringsSep "\n" (map (e: "${e.address} ${e.name}.home") validEntries) + "\n";
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
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.dnsproxy} --cache ${listen} -u ${primaryDNS} -f ${secondaryDNS} -b ${bootstrapDNS} --timeout=500ms --hosts-file-enabled --hosts-files=/etc/hosts.local";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      };
    };
  };
}
