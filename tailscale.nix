{
  config,
  lib,
  ...
}:
let

  extraRouteFlags =
    if (config.my.tailscale.subnetRoutes != [ ]) then
      "--advertise-routes=" + (lib.concatStringsSep "," config.my.tailscale.subnetRoutes)
    else
      "";

  extraNetfilterFlags = if config.my.tailscale.netfilterModeOff then "--netfilter-mode=off" else "";

  extraSshFlags = if config.my.tailscale.enableSsh then "--ssh" else "";

in
{
  imports = [
    ./modules/tailscale-oauth.nix
  ];
  services = lib.mkIf config.my.tailscale.enable {
    tailscale-oauth = {
      enable = true;
      extraUpFlags = builtins.concatLists [
        config.my.tailscale.extraUpFlags
        [
          "--reset"
          extraRouteFlags
          extraNetfilterFlags
          extraSshFlags
        ]
      ];
      inherit (config.my.tailscale) oAuthClientIdPath oAuthClientSecretPath tags;
    };
  };
}
