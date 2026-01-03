{ lib, ... }:
with lib;
with types;
{
  options.private = {
    user = {
      name = mkOption {
        type = str;
        description = "Username for the primary user account";
      };
      fullName = mkOption {
        type = str;
        description = "Full name for the primary user";
      };
      email = mkOption {
        type = str;
        description = "Email address for notifications and git config";
      };
      sshKeys = mkOption {
        type = listOf str;
        default = [ ];
        description = "SSH public keys for the primary user";
      };
    };

    domain = mkOption {
      type = str;
      description = "Primary domain (e.g., example.com)";
    };

    aws = {
      accountId = mkOption {
        type = str;
        description = "AWS Account ID";
      };
      region = mkOption {
        type = str;
        default = "us-east-1";
        description = "AWS region";
      };
      route53ZoneId = mkOption {
        type = str;
        description = "Route53 hosted zone ID for dynamic DNS";
      };
      iamRoleName = mkOption {
        type = str;
        description = "IAM role name for Route53 updates";
      };
      sesUsername = mkOption {
        type = str;
        description = "AWS SES SMTP username (access key ID)";
      };
    };

    healthchecks = {
      pingKey = mkOption {
        type = str;
        description = "Healthchecks.io ping key for monitoring";
      };
      checkSlug = mkOption {
        type = str;
        default = "router-update-public-ip-in-route53";
        description = "Healthchecks.io check slug";
      };
    };

    proxyUser = {
      sshKeys = mkOption {
        type = listOf str;
        default = [ ];
        description = "SSH public keys for the proxy user";
      };
    };

    loki = {
      endpoint = mkOption {
        type = str;
        description = "Loki endpoint URL for log shipping";
      };
    };

    hosts = mkOption {
      type = attrsOf (listOf str);
      default = { };
      description = "Extra /etc/hosts entries (IP -> hostnames)";
    };

    ip_manifest = mkOption {
      type = attrsOf (
        listOf (submodule {
          options = {
            address = mkOption {
              type = str;
              description = "IP address";
            };
            macAddress = mkOption {
              type = str;
              description = "Device MAC address";
            };
            vendor = mkOption {
              type = str;
              default = "";
              description = "Hardware vendor (from OUI lookup)";
            };
            assignment = mkOption {
              type = enum [
                "dhcp"
                "static"
              ];
              default = "dhcp";
              description = "How the IP is assigned (dhcp = from DHCP server, static = configured on device)";
            };
            name = mkOption {
              type = str;
              default = "";
              description = "Device name/hostname";
            };
          };
        })
      );
      default = { };
      description = "Complete manifest of all known IP assignments by network";
    };
  };
}
