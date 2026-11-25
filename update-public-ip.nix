{
  pkgs,
  config,
  lib,
  ...
}:
let
  wanIface = "enp1s0";
  homeDomain = "home.${config.private.domain}";
  hostedZoneId = "Z01395942TRRYPPRD81J7";
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
    export AWS_ACCESS_KEY_ID="$(cat ${config.age.secrets.home-ddns-key-id.path})"
    export AWS_SECRET_ACCESS_KEY="$(cat ${config.age.secrets.home-ddns-secret.path})"

    wan_ip=$(${lib.getBin pkgs.iproute2}/bin/ip -json addr show dev ${wanIface} | ${lib.getExe pkgs.jq} -r '.[0] | .addr_info[] | select(.family == "inet")| .local')
    echo "WAN IP: ''${wan_ip}"

    if ${shellUtils}/bin/is-private-ip "$wan_ip"; then
      echo "$wan_ip is a Private IP. Exiting."
      exit 0
    else
     echo "$wan_ip is a Public IP. Proceeding."
    fi

    dns_ip=$(
      ${lib.getExe pkgs.curl} --fail --silent --show-error --max-time 10 \
        "https://dns.google/resolve?name=${homeDomain}&type=A" \
        | ${lib.getExe pkgs.jq} -r '[.Answer[]? | select(.type == 1)][0].data // empty'
    )
    echo "DNS IP: ''${dns_ip}"

    if [ "''${wan_ip}" != "''${dns_ip}" ]; then
    change_file=$(${pkgs.coreutils}/bin/mktemp)
    trap '${pkgs.coreutils}/bin/rm -f "$change_file"' EXIT
    ${pkgs.coreutils}/bin/cp ${r53template} "$change_file"
    ${pkgs.gnused}/bin/sed -i "s/IP_TO_REPLACE/''${wan_ip}/" "$change_file"
    ${lib.getExe pkgs.awscli2} route53 change-resource-record-sets \
      --hosted-zone-id ${hostedZoneId} \
      --change-batch "file://$change_file" \
      --query 'ChangeInfo.{Id:Id,Status:Status}' \
      --output json

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
            CHECK_SLUG = config.private.healthchecks.checkSlug;
          };
          serviceConfig = {
            Type = "oneshot";
            User = config.private.user.name;
            Group = "users";
          };
          script = ''
            export HC_PING_KEY="$(cat ${config.age.secrets.healthchecks-io-ping-key.path})"
            test -n "$HC_PING_KEY"
            exec ${lib.getExe pkgs.runitor} ${lib.getExe update_ip}
          '';
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
