{
  pkgs,
  config,
  lib,
  ...
}:
let
  wanIface = "enp1s0";
  homeDomain = "home.${config.private.domain}";
  shellUtils = pkgs.callPackage ./packages/shell-utils/shell-utils.nix { };

  # Generate the Route53 change batch JSON dynamically
  r53template = pkgs.writeText "r53template.json" (
    builtins.toJSON {
      Comment = "Update home IP address";
      Changes = [
        {
          Action = "UPSERT";
          ResourceRecordSet = {
            Name = "${homeDomain}.";
            Type = "A";
            TTL = 300;
            ResourceRecords = [ { Value = "IP_TO_REPLACE"; } ];
          };
        }
      ];
    }
  );

  update_ip = pkgs.writeShellScriptBin "update_ip" ''
    export AWS_DEFAULT_REGION=${config.private.aws.region}
    export AWS_ACCESS_KEY_ID="$(cat ${config.age.secrets.aws-domain-mgr-key-id.path})"
    export AWS_SECRET_ACCESS_KEY="$(cat ${config.age.secrets.aws-domain-mgr-secret.path})"
    IAM_ROLE_ARN=arn:aws:iam::${config.private.aws.accountId}:role/${config.private.aws.iamRoleName}
    HOSTED_ZONE_ID=${config.private.aws.route53ZoneId}

    sess_creds=$(${lib.getExe pkgs.awscli} sts assume-role --role-arn $IAM_ROLE_ARN --role-session-name update_ip)

    export AWS_ACCESS_KEY_ID=$(echo $sess_creds | ${lib.getExe pkgs.jq} -r .Credentials.AccessKeyId)
    export AWS_SECRET_ACCESS_KEY=$(echo $sess_creds | ${lib.getExe pkgs.jq} -r .Credentials.SecretAccessKey)
    export AWS_SESSION_TOKEN=$(echo $sess_creds | ${lib.getExe pkgs.jq} -r .Credentials.SessionToken)

    echo $(${lib.getExe pkgs.awscli} sts get-caller-identity)

    wan_ip=$(${lib.getBin pkgs.iproute2}/bin/ip -json addr show dev ${wanIface} | ${lib.getExe pkgs.jq} -r '.[0] | .addr_info[] | select(.family == "inet")| .local')
    echo "WAN IP: ''${wan_ip}"

    if ${shellUtils}/bin/is-private-ip "$wan_ip"; then
      echo "$wan_ip is a Private IP. Exiting."
      exit 0
    else
     echo "$wan_ip is a Public IP. Proceeding."
    fi

    dns_ip=$(${lib.getExe pkgs.awscli} route53 list-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --output json | ${lib.getExe pkgs.jq} -r '.ResourceRecordSets[] | select(.Name == "${homeDomain}.") | .ResourceRecords[0].Value')
    echo "DNS IP: ''${dns_ip}"

    rm -rf /tmp/update-ip/
    mkdir -p /tmp/update-ip/

    if [ "''${wan_ip}" != "''${dns_ip}" ]; then
    cp ${r53template} /tmp/update-ip/t.json
    sed -i "s/IP_TO_REPLACE/''${wan_ip}/" /tmp/update-ip/t.json
    ${lib.getExe pkgs.awscli} route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch file:///tmp/update-ip/t.json

    rm -rf /tmp/update-ip/

    email_body="Old IP: ''${dns_ip}. New IP: ''${wan_ip}"

    echo "$email_body" | ${config.my.emailSending.scripts.msmtp-wrap}/bin/msmtp-wrap "ignore" "${homeDomain} Address Changed" "${config.my.emailSending.to}"

    else
    echo "IPs the same, doing nothing"
    fi
  '';

in
{
  config = {
    systemd = {
      services = {
        updateRoute53 = {
          wants = [ "updateRoute53Timer.timer" ];
          description = "Update public IP in Route53 DNS record";
          environment = {
            HC_PING_KEY = config.private.healthchecks.pingKey;
            CHECK_SLUG = config.private.healthchecks.checkSlug;
          };
          serviceConfig = {
            Type = "oneshot";
            User = config.private.user.name;
            Group = "users";
          };
          script = "${lib.getExe pkgs.runitor} ${lib.getExe update_ip}";
        };
      };
      timers = {
        updateRoute53Timer = {
          description = "Timer for the updateRoute53 service";
          wantedBy = [ "timers.target" ];
          requires = [ "updateRoute53.service" ];
          timerConfig = {
            OnCalendar = "*-*-* *:00:00";
            Unit = "updateRoute53.service";
          };
        };
      };
    };
  };
}
