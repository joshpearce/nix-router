{
  pkgs,
  lib,
  config,
  ...
}:
let
  textfileDirectory = "/var/lib/node-exporter/textfile";
  routerHealthCollector = pkgs.writeShellApplication {
    name = "collect-router-health";
    runtimeInputs = with pkgs; [
      bind.dnsutils
      coreutils
      gawk
      gnugrep
      iproute2
      systemd
    ];
    text = builtins.readFile ./scripts/collect-router-health.sh;
  };
in
{
  systemd = {
    services = {
      node-exporter = {
        wantedBy = [ "multi-user.target" ];
        description = "Prometheus exporter for hardware and OS metrics";
        serviceConfig = {
          Type = "simple";
          StateDirectory = "node-exporter";
          StandardOutput = "journal";
          StandardError = "journal";
        };
        script = ''
          exec ${lib.getExe pkgs.prometheus-node-exporter} \
            --collector.textfile.directory=${textfileDirectory}
        '';
      };

      router-health-metrics = {
        description = "Collect passive router correctness metrics";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "node-exporter";
          Environment = [
            "TEXTFILE_DIRECTORY=${textfileDirectory}"
            "PUBLIC_DNS_NAME=home.${config.private.domain}"
          ];
        };
        script = "${lib.getExe routerHealthCollector}";
      };
    };

    timers.router-health-metrics = {
      description = "Collect passive router correctness metrics every minute";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = "1m";
        AccuracySec = "10s";
        Unit = "router-health-metrics.service";
      };
    };
  };
}
