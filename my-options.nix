{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with types;
{
  options.my = {
    emailSending = {
      zfs = {
        enable = mkEnableOption "Support emailing ZFS events";
      };
      to = mkOption {
        type = str;
        default = config.private.user.email;
      };
      scripts = mkOption {
        type = attrs;
        default = {
          msmtp-wrap = pkgs.writeShellScriptBin "msmtp-wrap" ''
            subject="$2"
            to="$3"
            orig_body=`cat`
            printf "Subject: $subject\n\n$orig_body" | ${pkgs.msmtp}/bin/msmtp -a default $to
          '';
        };
      };
      enable = mkOption {
        type = bool;
        default = config.my.emailSending.zfs.enable;
      };
      from = mkOption {
        type = str;
        default = "notify@${config.private.domain}";
      };
      host = mkOption {
        type = str;
        default = "email-smtp.${config.private.aws.region}.amazonaws.com";
      };
      port = mkOption {
        type = port;
        default = 587;
      };
      user = mkOption {
        type = str;
        default = config.private.aws.sesUsername;
      };
      passwordeval = mkOption {
        type = str;
        default = "cat ${config.age.secrets.ses-smtp-user.path}";
      };
    };
    vsCodeServer = mkEnableOption "Support for remote development";
    tailscale = {
      enable = mkEnableOption "Support tailscale";
      netfilterModeOff = mkEnableOption "Disable netfilter rules";
      enableSsh = mkEnableOption "Enable tailscale SSH feature";
      subnetRoutes = mkOption {
        type = listOf str;
        default = [ ];
      };
      extraUpFlags = mkOption {
        type = listOf str;
        default = [ ];
      };
      oAuthClientIdPath = mkOption {
        type = str;
        default = config.age.secrets.ts-oauth-client-id.path;
      };
      oAuthClientSecretPath = mkOption {
        type = str;
        default = config.age.secrets.ts-oauth-client-secret.path;
      };
      tags = mkOption {
        type = listOf str;
        default = [ "tag:lan" ];
      };
    };
  };
}
