{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.tailscale-oauth;
  tsOauthScripts = pkgs.callPackage ../packages/tailscale-oauth/tailscale-oauth.nix { };
  shellUtils = pkgs.callPackage ../packages/shell-utils/shell-utils.nix { };
  wanIface = "enp1s0";
  authKeyFlag =
    if (cfg.authKeyFile != null) then
      " --auth-key 'file:${cfg.authKeyFile}'"
    else if (cfg.oAuthClientIdPath != null && cfg.oAuthClientSecretPath != null) then
      "--auth-key=$(${tsOauthScripts}/bin/ts-get-auth-key $(cat ${cfg.oAuthClientIdPath}) $(cat ${cfg.oAuthClientSecretPath}) \"${lib.strings.concatStringsSep ", " cfg.tags}\")"
    else
      "";
  deleteDevice =
    if (cfg.oAuthClientIdPath != null && cfg.oAuthClientSecretPath != null) then
      "${tsOauthScripts}/bin/ts-delete-node $(cat ${cfg.oAuthClientIdPath}) $(cat ${cfg.oAuthClientSecretPath}) $(${pkgs.nettools}/bin/hostname)"
    else
      "";
in
{
  meta.maintainers = with maintainers; [
    danderson
    mbaillie
    twitchyliquid64
    mfrw
  ];

  options.services.tailscale-oauth = {
    enable = mkEnableOption (lib.mdDoc "Tailscale client daemon");

    port = mkOption {
      type = types.port;
      default = 41641;
      description = lib.mdDoc "The port to listen on for tunnel traffic (0=autoselect).";
    };

    interfaceName = mkOption {
      type = types.str;
      default = "tailscale0";
      description = lib.mdDoc ''The interface name for tunnel traffic. Use "userspace-networking" (beta) to not use TUN.'';
    };

    permitCertUid = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      description = lib.mdDoc "Username or user ID of the user allowed to to fetch Tailscale TLS certificates for the node.";
    };

    package = lib.mkPackageOption pkgs "tailscale" { };

    openFirewall = mkOption {
      default = false;
      type = types.bool;
      description = lib.mdDoc "Whether to open the firewall for the specified port.";
    };

    useRoutingFeatures = mkOption {
      type = types.enum [
        "none"
        "client"
        "server"
        "both"
      ];
      default = "none";
      example = "server";
      description = lib.mdDoc ''
        Enables settings required for Tailscale's routing features like subnet routers and exit nodes.

        To use these these features, you will still need to call `sudo tailscale up` with the relevant flags like `--advertise-exit-node` and `--exit-node`.

        When set to `client` or `both`, reverse path filtering will be set to loose instead of strict.
        When set to `server` or `both`, IP forwarding will be enabled.
      '';
    };

    authKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/tailscale_key";
      description = lib.mdDoc ''
        A file containing the auth key.
      '';
    };

    extraUpFlags = mkOption {
      description = lib.mdDoc "Extra flags to pass to {command}`tailscale up`.";
      type = types.listOf types.str;
      default = [ ];
      example = [ "--ssh" ];
    };

    oAuthClientIdPath = lib.mkOption {
      type = lib.types.str;
      default = "none";
    };

    oAuthClientSecretPath = lib.mkOption {
      type = lib.types.str;
      default = "none";
    };

    tags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    oAuthRefreshInterval = mkOption {
      default = "*-*-01 02:00";
      type = types.str;
      example = "Sun *-*-* 00:00:00";
      description = lib.mdDoc "Systemd timerConfig OnCalendar interval to delete and recreate/reauth device.";
    };

  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ]; # for the CLI
    systemd = {
      packages = [ cfg.package ];
      services.tailscaled = {
        wantedBy = [ "multi-user.target" ];
        path = [
          pkgs.procps # for collecting running services (opt-in feature)
          pkgs.getent # for `getent` to look up user shells
          pkgs.kmod # required to pass tailscale's v6nat check
        ]
        ++ lib.optional config.networking.resolvconf.enable config.networking.resolvconf.package;
        serviceConfig.Environment = [
          "PORT=${toString cfg.port}"
          ''"FLAGS=--tun ${lib.escapeShellArg cfg.interfaceName}"''
        ]
        ++ (lib.optionals (cfg.permitCertUid != null) [
          "TS_PERMIT_CERT_UID=${cfg.permitCertUid}"
        ]);
        # Restart tailscaled with a single `systemctl restart` at the
        # end of activation, rather than a `stop` followed by a later
        # `start`. Activation over Tailscale can hang for tens of
        # seconds in the stop+start setup, if the activation script has
        # a significant delay between the stop and start phases
        # (e.g. script blocked on another unit with a slow shutdown).
        #
        # Tailscale is aware of the correctness tradeoff involved, and
        # already makes its upstream systemd unit robust against unit
        # version mismatches on restart for compatibility with other
        # linux distros.
        stopIfChanged = false;
      };

      services.tailscaled-autoconnect = mkIf (cfg.authKeyFile != null || cfg.extraUpFlags != [ ]) {
        after = [ "tailscaled.service" ];
        wants = [ "tailscaled.service" ];
        serviceConfig = {
          Type = "oneshot";
        };
        script =
          let
            statusCommand = "${lib.getExe cfg.package} status --json --peers=false | ${lib.getExe pkgs.jq} -r '.BackendState'";
            get_wan_ip = "${lib.getBin pkgs.iproute2}/bin/ip -json addr show dev ${wanIface} | ${lib.getExe pkgs.jq} -r '.[0] | .addr_info[] | select(.family == \"inet\")| .local'";
          in
          ''
            wan_ip=$(${get_wan_ip})
            if ${shellUtils}/bin/is-private-ip "$wan_ip"; then
              echo "WAN IP, $wan_ip is a private IP. Exiting."
              exit 0
            fi
            while [[ "$(${statusCommand})" == "NoState" ]]; do
              sleep 0.5
            done
            status=$(${statusCommand})
            if [[ "$status" == "NeedsLogin" || "$status" == "NeedsMachineAuth" ]]; then
              ${deleteDevice}
              ${cfg.package}/bin/tailscale up ${authKeyFlag} ${concatStringsSep " " cfg.extraUpFlags}
            fi
          '';
      };

      timers.tailscaled-autoconnect =
        mkIf (cfg.oAuthClientIdPath != null && cfg.oAuthClientSecretPath != null)
          {
            description = "Timer for the tailscaled-autoconnect service";
            wantedBy = [ "timers.target" ];
            requires = [ "tailscaled-autoconnect.service" ];
            timerConfig = {
              OnCalendar = cfg.oAuthRefreshInterval;
              Persistent = "yes";
              Unit = "tailscaled-autoconnect.service";
            };
          };

      network.networks."50-tailscale" = {
        matchConfig = {
          Name = cfg.interfaceName;
        };
        linkConfig = {
          Unmanaged = true;
          ActivationPolicy = "manual";
        };
      };
    };

    boot.kernel.sysctl = mkIf (cfg.useRoutingFeatures == "server" || cfg.useRoutingFeatures == "both") {
      "net.ipv4.conf.all.forwarding" = mkOverride 97 true;
      "net.ipv6.conf.all.forwarding" = mkOverride 97 true;
    };

    networking = {
      firewall = {
        allowedUDPPorts = mkIf cfg.openFirewall [ cfg.port ];
        checkReversePath = mkIf (
          cfg.useRoutingFeatures == "client" || cfg.useRoutingFeatures == "both"
        ) "loose";
      };
      dhcpcd.denyInterfaces = [ cfg.interfaceName ];
    };
  };
}
