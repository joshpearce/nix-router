{
  pkgs,
  lib,
  ...
}:
{
  systemd = {
    services = {
      node-exporter = {
        wantedBy = [ "multi-user.target" ];
        description = "Prometheus exporter for hardware and OS metrics";
        serviceConfig = {
          Type = "simple";
          StandardOutput = "journal";
          StandardError = "journal";
        };
        script = "${lib.getExe pkgs.prometheus-node-exporter}";
      };
    };
  };
}
