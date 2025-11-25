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
        "log1:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str1:IP2STR,print1:PRINTPKT,syslog1:SYSLOG"
        "ct1:NFCT,ip2str1:IP2STR,print1:PRINTFLOW,syslog2:SYSLOG"
      ];
    };
    log1 = {
      group = 1;
    }; # NFLOG config
    ct1 = { }; # NFCT config (uses defaults)

    syslog1 = {
      facility = "LOG_LOCAL1";
      level = "LOG_INFO";
    };
    syslog2 = {
      facility = "LOG_LOCAL1";
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
