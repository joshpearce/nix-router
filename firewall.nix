{ config, ... }:
let
  wanIface = "enp1s0";
  lanIface = "enp2s0";
  tsIface = "tailscale0";
  lanVlan = "lan";
  iotVlan = "iot";
  k8sVlan = "k8s";
  hazmatVlan = "hazmat";
  guestVlan = "guest";

  # IP lookup helpers - explicitly list networks for reliable NixOS module evaluation
  allDevices =
    (config.private.ip_manifest.mgmt or [ ])
    ++ (config.private.ip_manifest.lan or [ ])
    ++ (config.private.ip_manifest.iot or [ ])
    ++ (config.private.ip_manifest.hazmat or [ ]);

  findDevice =
    name:
    let
      matches = builtins.filter (d: d.name == name) allDevices;
    in
    if matches == [ ] then null else builtins.head matches;

  getIp =
    name:
    let
      device = findDevice name;
    in
    if device == null then
      builtins.throw "firewall.nix: Device '${name}' not found in ip_manifest"
    else
      device.address;

  getIps = names: builtins.concatStringsSep ", " (map getIp names);

  # Named hosts - looked up from ip_manifest
  homeAssistant = getIp "homeassistant";
  nas = getIp "nas";
  cloudKey = getIp "CloudKey2";
  blockedIotDevices = getIps [
    "wiz1"
    "wiz2"
    "printer"
  ];

in
{
  config = {
    networking = {
      firewall.enable = false;
      nftables = {
        enable = true;
        ruleset = ''
          # Known DoT/DoH providers - for encrypted DNS detection
          define encrypted_dns_servers = {
            1.1.1.1, 1.0.0.1,                             # Cloudflare
            8.8.8.8, 8.8.4.4,                             # Google
            9.9.9.9, 149.112.112.112,                     # Quad9: +malware,+dnssec,-ecs
            9.9.9.10, 149.112.112.10,                     # Quad9: -malware,-dnssec,-ecs
            9.9.9.11, 149.112.112.11                      # Quad9: +malware,+dnssec,+ecs
          }

          table ip filter {
            chain rp_audit {
              type filter hook prerouting priority -300; policy accept;

              # Log packets arriving on WAN addressed to internal IPs (would fail strict rp_filter)
              iifname "${wanIface}" ip daddr { 192.168.1.1, 10.13.84.1, 10.13.86.1, 10.13.93.1, 10.13.83.1, 10.13.99.1, 100.114.201.26 } log group 4 prefix "RP-AUDIT-WAN: "

              # Log packets arriving on internal interfaces addressed to WAN IP
              iifname { "${lanIface}", "${lanVlan}", "${k8sVlan}", "${iotVlan}", "${guestVlan}", "${hazmatVlan}" } ip daddr 99.85.28.23 log group 4 prefix "RP-AUDIT-INT: "

              # Log packets arriving on one internal interface addressed to another's IP
              iifname "${lanIface}" ip daddr { 10.13.84.1, 10.13.86.1, 10.13.93.1, 10.13.83.1, 10.13.99.1 } log group 4 prefix "RP-AUDIT-CROSS: "
              iifname "${lanVlan}" ip daddr { 192.168.1.1, 10.13.86.1, 10.13.93.1, 10.13.83.1, 10.13.99.1 } log group 4 prefix "RP-AUDIT-CROSS: "
              iifname "${k8sVlan}" ip daddr { 192.168.1.1, 10.13.84.1, 10.13.93.1, 10.13.83.1, 10.13.99.1 } log group 4 prefix "RP-AUDIT-CROSS: "
              iifname "${iotVlan}" ip daddr { 192.168.1.1, 10.13.84.1, 10.13.86.1, 10.13.83.1, 10.13.99.1 } log group 4 prefix "RP-AUDIT-CROSS: "
              iifname "${guestVlan}" ip daddr { 192.168.1.1, 10.13.84.1, 10.13.86.1, 10.13.93.1, 10.13.99.1 } log group 4 prefix "RP-AUDIT-CROSS: "
              iifname "${hazmatVlan}" ip daddr { 192.168.1.1, 10.13.84.1, 10.13.86.1, 10.13.93.1, 10.13.83.1 } log group 4 prefix "RP-AUDIT-CROSS: "

              # Tailscale logged separately - its traffic patterns may legitimately cross interfaces
              iifname "${tsIface}" ip daddr { 192.168.1.1, 10.13.84.1, 10.13.86.1, 10.13.93.1, 10.13.83.1, 10.13.99.1, 99.85.28.23 } log group 4 prefix "RP-AUDIT-TS: "
            }
            chain trace_chain {
              type filter hook prerouting priority -1;
              iifname { "${tsIface}" } nftrace set 0 comment "set to 1 to enable"
            }
            chain input {
              type filter hook input priority 0; policy drop;
              iif lo accept
              counter jump ts-input
              ip saddr 127.0.0.0/8 counter drop
              iifname { "${iotVlan}" } ct state { established, related } counter accept comment "Allow established traffic back to router from iot"
              iifname { "${lanIface}" } accept comment "Allow port to access the router"
              iifname { "${lanVlan}" } accept comment "Allow vlan lan to access the router"
              iifname { "${k8sVlan}" } accept comment "Allow vlan k8s to access the router"
              iifname { "${wanIface}" } ct state { established, related } accept comment "Allow established wan traffic"
              iifname { "${tsIface}" } accept comment "Allow established tailscale traffic"
              iifname { "${wanIface}", "${tsIface}" } icmp type { echo-request } limit rate 10/second counter accept comment "Allow ICMP ping with rate limit"
              iifname { "${wanIface}", "${tsIface}" } icmp type { destination-unreachable, time-exceeded } counter accept comment "Allow ICMP errors"
              iifname { "${wanIface}" } tcp dport { 8044 } counter drop comment "Temporarily port 8044 for ssh"
              iifname { "${iotVlan}" } ip saddr { ${homeAssistant} } udp dport { mdns } counter accept comment "multicast for media devices, printers"
              iifname { "${iotVlan}" } udp dport { 53, 123 } counter accept comment "Allow dns and time from iot to local dns proxy and chrony servers"
              iifname { "${hazmatVlan}", "${iotVlan}", "${guestVlan}" } udp dport 67 accept comment "Allow DHCP Discover and Request message to reach the router"
              iifname "${wanIface}" counter drop comment "Drop all other unsolicited traffic from wan"
            }
            chain ts-input {
              iifname "lo" ip saddr 100.75.230.100 counter accept
              iifname != "${tsIface}" ip saddr 100.115.92.0/23 counter return
              iifname != "${tsIface}" ip saddr 100.64.0.0/10 counter drop
            }
            chain forward {
              type filter hook forward priority 0; policy drop;
              counter jump ts-forward
              ct state invalid counter drop comment "Drop invalid connections"
              ct state { established, related } accept comment "Allow all established/related"

              # Log connections to known DoT/DoH providers (NFLOG group 3)
              iifname { "${lanIface}", "${lanVlan}", "${iotVlan}", "${k8sVlan}" } ip daddr $encrypted_dns_servers tcp dport { 443, 853 } ct state new log group 3 prefix "ENCRYPTED-DNS: "

              # Route to per-zone chains
              iifname { "${lanIface}" } jump from-mgmt
              iifname { "${lanVlan}" } jump from-lan
              iifname { "${k8sVlan}" } jump from-k8s
              iifname { "${iotVlan}" } jump from-iot
              iifname { "${guestVlan}" } jump from-guest
              iifname { "${hazmatVlan}" } jump from-hazmat
              iifname { "${tsIface}" } jump from-tailscale
            }

            chain from-mgmt {
              oifname { "${wanIface}" } accept comment "Mgmt to WAN"
            }

            chain from-lan {
              oifname { "${wanIface}" } accept comment "LAN to WAN"
              oifname { "${iotVlan}" } accept comment "LAN to IoT"
              oifname { "${k8sVlan}" } accept comment "LAN to k8s"
              ip daddr 192.168.1.0/24 accept comment "LAN to Mgmt network"
            }

            chain from-k8s {
              oifname { "${wanIface}" } accept comment "k8s to WAN"
              oifname { "${k8sVlan}" } accept comment "k8s hairpin"
              oifname { "${iotVlan}" } accept comment "k8s to IoT"
            }

            chain from-iot {
              ip saddr { ${blockedIotDevices} } oifname { "${wanIface}" } counter drop comment "Block select IoT devices from internet"
              oifname { "${wanIface}" } accept comment "IoT to WAN"
              ip saddr ${homeAssistant} ip daddr ${nas} tcp dport { 22, 3493, 5432 } accept comment "HA to NAS (ssh, NUT, postgres)"
              ip saddr ${homeAssistant} ip daddr ${cloudKey} tcp dport { 443 } accept comment "HA to CloudKey"
            }

            chain from-guest {
              oifname { "${wanIface}" } accept comment "Guest to WAN only"
            }

            chain from-hazmat {
              oifname { "${wanIface}" } accept comment "Hazmat to WAN only"
            }

            chain from-tailscale {
              ip daddr { ${getIp "NAS-IPMI"}, ${homeAssistant}, ${getIp "WINDOWS-VM1"} } accept comment "Tailscale subnet routing"
            }

            chain ts-forward {
              iifname "${tsIface}" counter meta mark set mark and 0xff00ffff xor 0x40000
              meta mark & 0x00ff0000 == 0x00040000 counter accept
              oifname "${tsIface}" ip saddr 100.64.0.0/10 counter drop
              oifname "${tsIface}" counter accept
            }
          }

          table ip nat {
            chain prerouting {
              type nat hook prerouting priority -100; policy accept;

              # Private networks - DNS to these doesn't need redirect
              define private_nets = { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }

              # Redirect DNS, NTP going to external servers through local dnsproxy
              # Uses NFLOG group 2 to keep separate from existing packet logs (group 1)
              # Only intercept VLANs that use local DNS (excludes guest/hazmat which use external)
              iifname { "${lanIface}", "${lanVlan}", "${iotVlan}", "${k8sVlan}" } udp dport 53 ip daddr != $private_nets log group 2 prefix "DNS-REDIRECT: " redirect
              iifname { "${lanIface}", "${lanVlan}", "${iotVlan}", "${k8sVlan}" } tcp dport 53 ip daddr != $private_nets log group 2 prefix "DNS-REDIRECT: " redirect
              iifname { "${lanIface}", "${lanVlan}", "${iotVlan}", "${k8sVlan}" } udp dport 123 ip daddr != $private_nets log group 2 prefix "NTP-REDIRECT: " redirect
            }
            chain postrouting {
              type nat hook postrouting priority 100; policy accept;
              counter jump ts-postrouting
              oifname "${wanIface}" masquerade
            }
            chain ts-postrouting {
              meta mark & 0x00ff0000 == 0x00040000 counter masquerade
            }
          }

          table ip6 filter {
            chain input {
              type filter hook input priority 0; policy drop;
            }
            chain forward {
              type filter hook forward priority 0; policy drop;
            }
          }
        '';

      };
    };
  };
}
