{ pkgs, ... }:
let
  settingsFormat = pkgs.formats.ini { listsAsDuplicateKeys = true; };
  settings = {
    global = {
      plugin = [
        "${pkgs.ulogd}/lib/ulogd/ulogd_raw2packet_BASE.so"
        "${pkgs.ulogd}/lib/ulogd/ulogd_inpflow_NFCT.so"
        "${pkgs.ulogd}/lib/ulogd/ulogd_inppkt_NFLOG.so"
        "${pkgs.ulogd}/lib/ulogd/ulogd_filter_IFINDEX.so"
        "${pkgs.ulogd}/lib/ulogd/ulogd_output_SYSLOG.so"
        "${pkgs.ulogd}/lib/ulogd/ulogd_filter_PRINTPKT.so"
        "${pkgs.ulogd}/lib/ulogd/ulogd_filter_PRINTFLOW.so"
        "${pkgs.ulogd}/lib/ulogd/ulogd_filter_IP2STR.so"
        "${pkgs.ulogd}/lib/ulogd/ulogd_inpflow_NFACCT.so"
        "${pkgs.ulogd}/lib/ulogd/ulogd_output_NACCT.so"
      ];

      stack = [
        # Packet logging (NFLOG group 1) - currently unused, no nftables rules send to group 1
        "log1:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str1:IP2STR,print1:PRINTPKT,syslog1:SYSLOG"
        # DNS redirect logging (NFLOG group 2) - from firewall.nix prerouting chain
        "log2:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str1:IP2STR,print1:PRINTPKT,syslog2:SYSLOG"
        # Encrypted DNS logging (NFLOG group 3) - DoT/DoH detection from firewall.nix forward chain
        "log3:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str1:IP2STR,print1:PRINTPKT,syslog3:SYSLOG"
        # Connection flow logging (conntrack) - automatic, no nftables rules needed
        "ct1:NFCT,ip2str1:IP2STR,print1:PRINTFLOW,syslog1:SYSLOG"
      ];
    };
    log1 = { group = 1; }; # NFLOG group 1 - packet logging (unused)
    log2 = { group = 2; }; # NFLOG group 2 - DNS redirect logging
    log3 = { group = 3; }; # NFLOG group 3 - encrypted DNS (DoT/DoH) logging
    ct1 = { };             # NFCT conntrack (uses defaults)

    # LOCAL1 for flow logs and general packet logs (consumed by Vector prep_for_metric)
    syslog1 = {
      facility = "LOG_LOCAL1";
      level = "LOG_INFO";
    };
    # LOCAL2 for DNS redirect logs (consumed by Vector parse_dns_redirect)
    syslog2 = {
      facility = "LOG_LOCAL2";
      level = "LOG_INFO";
    };
    # LOCAL3 for encrypted DNS logs (consumed by Vector parse_encrypted_dns)
    syslog3 = {
      facility = "LOG_LOCAL3";
      level = "LOG_INFO";
    };
  };
  settingsFile = settingsFormat.generate "ulogd.conf" settings;
  logLevel = 3; # (1 = debug, 3 = info, 5 = notice, 7 = error, 8 = fatal)
in
{
  config = {
    systemd.services.ulogd = {
      description = "Ulogd Daemon";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-pre.target" ];
      before = [ "network-pre.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.ulogd}/bin/ulogd -c ${settingsFile} --verbose --loglevel ${toString logLevel}";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      };
    };
  };
}
