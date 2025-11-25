{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.services.vector2;

in
{
  options.services.vector2 = {
    enable = mkEnableOption (lib.mdDoc "Vector");

    package = mkPackageOption pkgs "vector" { };

    journaldAccess = mkOption {
      type = types.bool;
      default = false;
      description = lib.mdDoc ''
        Enable Vector to access journald.
      '';
    };

    settings = mkOption {
      inherit (pkgs.formats.json { }) type;
      default = { };
      description = lib.mdDoc ''
        Specify the configuration for Vector in Nix.
      '';
    };
  };

  config = mkIf cfg.enable {
    # for cli usage
    environment.systemPackages = [ pkgs.vector ];

    systemd.services.vector = {
      description = "Vector event and log aggregator";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      requires = [ "network-online.target" ];
      serviceConfig =
        let
          format = pkgs.formats.json { };
          conf = format.generate "vector.json" cfg.settings;
          validateConfig =
            file:
            pkgs.runCommand "validate-vector-conf.json"
              {
                nativeBuildInputs = [ pkgs.vector ];
              }
              ''
                vector validate --no-environment "${file}"
                ln -s "${file}" "$out"
              '';
        in
        {
          ExecStart = "${lib.getExe cfg.package} --config ${validateConfig conf}";
          DynamicUser = true;
          Restart = "no";
          StateDirectory = "vector";
          ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
          AmbientCapabilities = "CAP_NET_BIND_SERVICE";
          # This group is required for accessing journald.
          SupplementaryGroups = mkIf cfg.journaldAccess "systemd-journal";
        };
    };
  };
}
