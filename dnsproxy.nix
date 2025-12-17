{
  pkgs,
  lib,
  ...
}:
let
  bootstrapDNS = "8.8.8.8:53";
  primaryDNS = "10.13.93.50:53";
  secondaryDNS = "https://9.9.9.10/dns-query";
  listen = "-l 192.168.1.1 -l 10.13.84.1 -l 10.13.93.1 -l 10.13.83.1 -l 10.13.99.1 -l 10.13.86.1 -p 53";
in
{
  config = {
    systemd.services.dnsproxy = {
      description = "DNS Proxy";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.dnsproxy} --cache ${listen} -u ${primaryDNS} -f ${secondaryDNS} -b ${bootstrapDNS} --timeout=500ms";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      };
    };
  };
}
