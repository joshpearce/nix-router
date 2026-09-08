{ pkgs }:
pkgs.runCommand "router-health-tests" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
  shellcheck ${../scripts/collect-router-health.sh}
  grep -q 'textfileDirectory = "/var/lib/node-exporter/textfile"' ${../node-exporter.nix}
  grep -q -- '--collector.textfile.directory=' ${../node-exporter.nix}
  grep -q 'PUBLIC_DNS_NAME=home.' ${../node-exporter.nix}
  grep -q 'install -d -m 0755' ${../scripts/collect-router-health.sh}
  grep -q 'homelab_router_dynamic_dns_record_matches_wan' ${../scripts/collect-router-health.sh}
  grep -q 'homelab_router_dhcp_active_leases' ${../scripts/collect-router-health.sh}
  touch "$out"
''
