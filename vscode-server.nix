{
  config,
  pkgs,
  lib,
  ...
}:
lib.mkIf config.my.vsCodeServer {
  services = {
    vscode-server = {
      enable = true;
      enableFHS = true;
      nodejsPackage = pkgs.nodejs_20;
    };
  };
}
