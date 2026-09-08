# shellcheck shell=bash
set -u

textfile_directory="${TEXTFILE_DIRECTORY:-/var/lib/node-exporter/textfile}"
output="${textfile_directory}/router-health.prom"
temporary="$(mktemp "${textfile_directory}/.router-health.XXXXXX")"
trap 'rm -f "$temporary"' EXIT HUP INT TERM

collector_success=1

metric() {
  printf '%s %s\n' "$1" "$2" >> "$temporary"
}

active_metric() {
  service="$1"
  if systemctl is-active --quiet "$service"; then
    value=1
  else
    value=0
  fi
  metric "homelab_router_service_active{host=\"nix-router\",unit=\"${service}\"}" "$value"
}

interface_metric() {
  interface="$1"
  state_file="/sys/class/net/${interface}/operstate"
  if [ -r "$state_file" ] && [ "$(cat "$state_file")" = "up" ]; then
    value=1
  else
    value=0
  fi
  metric "homelab_router_interface_up{host=\"nix-router\",interface=\"${interface}\"}" "$value"
}

dns_metric() {
  kind="$1"
  name="$2"
  expected="$3"
  response="$(dig +time=2 +tries=1 +noall +answer +stats @127.0.0.1 A "$name" 2>/dev/null)" || response=""
  answer="$(printf '%s\n' "$response" | awk '$1 !~ /^;/ && $4 == "A" { print $5; exit }')"
  query_milliseconds="$(printf '%s\n' "$response" | awk '/Query time:/ { print $4; exit }')"
  if [ -n "$answer" ] && { [ -z "$expected" ] || [ "$answer" = "$expected" ]; }; then
    success=1
  else
    success=0
  fi
  metric "homelab_router_dns_query_success{host=\"nix-router\",kind=\"${kind}\"}" "$success"
  metric "homelab_router_dns_query_duration_seconds{host=\"nix-router\",kind=\"${kind}\"}" "$(awk -v milliseconds="${query_milliseconds:-0}" 'BEGIN { printf "%.3f", milliseconds / 1000 }')"
}

printf '%s\n' \
  '# HELP homelab_router_collector_success Whether the passive router collector completed.' \
  '# TYPE homelab_router_collector_success gauge' \
  '# HELP homelab_router_service_active Whether an expected router service is active.' \
  '# TYPE homelab_router_service_active gauge' \
  '# HELP homelab_router_interface_up Whether an expected router interface reports operstate up.' \
  '# TYPE homelab_router_interface_up gauge' \
  '# HELP homelab_router_default_route_present Whether an IPv4 default route is present.' \
  '# TYPE homelab_router_default_route_present gauge' \
  '# HELP homelab_router_ipv4_forwarding_enabled Whether kernel IPv4 forwarding is enabled.' \
  '# TYPE homelab_router_ipv4_forwarding_enabled gauge' \
  '# HELP homelab_router_dns_query_success Whether a bounded DNS canary returned the expected answer class.' \
  '# TYPE homelab_router_dns_query_success gauge' \
  '# HELP homelab_router_dns_query_duration_seconds Duration of the bounded DNS canary query.' \
  '# TYPE homelab_router_dns_query_duration_seconds gauge' \
  '# HELP homelab_router_dhcp_active_leases Number of leases currently offered by systemd-networkd.' \
  '# TYPE homelab_router_dhcp_active_leases gauge' \
  '# HELP homelab_router_dhcp_pool_size Configured dynamic DHCP pool size.' \
  '# TYPE homelab_router_dhcp_pool_size gauge' \
  '# HELP homelab_router_dynamic_dns_last_success_timestamp_seconds Last successful dynamic-DNS unit completion.' \
  '# TYPE homelab_router_dynamic_dns_last_success_timestamp_seconds gauge' \
  '# HELP homelab_router_dynamic_dns_record_matches_wan Whether public DNS matches the current WAN address.' \
  '# TYPE homelab_router_dynamic_dns_record_matches_wan gauge' \
  > "$temporary"

for service in systemd-networkd.service dnsproxy.service chronyd.service vector.service; do
  active_metric "$service"
done

for interface in enp1s0 enp2s0 lan iot k8s guest hazmat; do
  interface_metric "$interface"
done

if ip -4 route show default | grep -q '^default '; then
  metric 'homelab_router_default_route_present{host="nix-router"}' 1
else
  metric 'homelab_router_default_route_present{host="nix-router"}' 0
fi

if [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" = "1" ]; then
  metric 'homelab_router_ipv4_forwarding_enabled{host="nix-router"}' 1
else
  metric 'homelab_router_ipv4_forwarding_enabled{host="nix-router"}' 0
fi

local_expected="$(awk '$2 == "nas.home" { print $1; exit }' /etc/hosts.local 2>/dev/null)"
dns_metric local nas.home "$local_expected"
dns_metric public example.com ""

for interface in enp2s0 lan iot k8s guest hazmat; do
  status="$(networkctl status "$interface" --no-pager 2>/dev/null)" || {
    status=""
    collector_success=0
  }
  leases="$(printf '%s\n' "$status" | awk '
    /Offered DHCP leases:/ {
      found=1
      if ($NF == "none") { print 0; done=1; exit }
      count=1
      next
    }
    found && /^[[:space:]]+[0-9]/ { count++; next }
    found { print count; done=1; exit }
    END { if (!done && found) print count; else if (!found) print -1 }
  ')"
  if [ "$leases" -lt 0 ]; then
    collector_success=0
  fi
  metric "homelab_router_dhcp_active_leases{host=\"nix-router\",interface=\"${interface}\"}" "$leases"
  metric "homelab_router_dhcp_pool_size{host=\"nix-router\",interface=\"${interface}\"}" 105
done

route53_result="$(systemctl show updateRoute53.service -p Result --value 2>/dev/null)" || route53_result=""
route53_timestamp="$(systemctl show updateRoute53.service -p ExecMainExitTimestamp --value 2>/dev/null)" || route53_timestamp=""
if [ "$route53_result" = "success" ] && route53_epoch="$(date --date="$route53_timestamp" +%s 2>/dev/null)"; then
  metric 'homelab_router_dynamic_dns_last_success_timestamp_seconds{host="nix-router"}' "$route53_epoch"
else
  metric 'homelab_router_dynamic_dns_last_success_timestamp_seconds{host="nix-router"}' 0
fi

wan_address="$(ip -4 -o address show dev enp1s0 2>/dev/null | awk '{ split($4, address, "/"); print address[1]; exit }')"
published_address="$(dig +time=2 +tries=1 +short @9.9.9.9 A "${PUBLIC_DNS_NAME:-}" 2>/dev/null | awk 'NF { print; exit }')"
if [ -n "$wan_address" ] && [ "$wan_address" = "$published_address" ]; then
  metric 'homelab_router_dynamic_dns_record_matches_wan{host="nix-router"}' 1
else
  metric 'homelab_router_dynamic_dns_record_matches_wan{host="nix-router"}' 0
fi

metric 'homelab_router_collector_success{host="nix-router"}' "$collector_success"
chmod 0644 "$temporary"
mv -f "$temporary" "$output"
trap - EXIT HUP INT TERM
