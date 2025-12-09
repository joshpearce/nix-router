_:
let
  wanIface = "enp1s0";
  lanIface = "enp2s0";
  tsIface = "tailscale0";
  lanVlan = "lan";
  iotVlan = "iot";
  k8sVlan = "k8s";
  hazmatVlan = "hazmat";
  guestVlan = "guest";

in
{
  config = {
    networking = {
      firewall.enable = false;
      nftables = {
        enable = true;
        ruleset = ''
          table ip filter {
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
              iifname { "${iotVlan}" } ip saddr { 10.13.93.14, 10.13.93.50 } udp dport { mdns } counter accept comment "multicast for media devices, printers"
              iifname { "${iotVlan}" } udp dport { 53 } counter accept comment "Allow dns from iot to local dns proxy"
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
              iifname { "${lanIface}" } oifname { "${wanIface}" } accept comment "Allow enp2s0 to WAN"
              iifname { "${lanVlan}" } oifname { "${wanIface}" } accept comment "Allow lan to WAN"
              iifname { "${k8sVlan}" } oifname { "${wanIface}" } accept comment "Allow k8s to WAN"
              iifname { "${k8sVlan}" } oifname { "${k8sVlan}" } accept comment "hairpinning on this iface"
              ip saddr { 10.13.93.16, 10.13.93.17, 10.13.93.14 } oifname { "${wanIface}" } counter drop comment "Block wiz bulbs and printer from internet"
              iifname { "${iotVlan}" } oifname { "${wanIface}" } accept comment "Allow iot to WAN"
              iifname { "${guestVlan}" } oifname { "${wanIface}" } accept comment "Allow guest to WAN"
              iifname { "${hazmatVlan}" } oifname { "${wanIface}" } accept comment "Allow hazmat to WAN"
              iifname { "${wanIface}" } oifname { "${lanIface}", "${lanVlan}", "${iotVlan}", "${guestVlan}", "${hazmatVlan}", "${k8sVlan}" } ct state { established, related } accept comment "Allow established back to All"
              iifname { "${lanVlan}", "${k8sVlan}" } oifname { "${iotVlan}" } counter accept comment "Allow trusted LAN to IoT"
              iifname { "${iotVlan}" } oifname { "${lanVlan}", "${k8sVlan}", "${tsIface}" } ct state { established, related } counter accept comment "Allow established from iot back to LANs"
              iifname { "${k8sVlan}" } oifname { "${lanVlan}" } ct state { established, related } counter accept comment "Allow established from k8s back to LAN"
              iifname { "${lanVlan}" } oifname { "${tsIface}" } ct state { established, related } counter accept comment "Allow established from LAN back to tailscale"
              iifname { "${lanVlan}" } ip daddr 192.168.1.0/24 counter accept comment "Allow trusted LAN to Mgmt (default)"
              iifname { "${lanVlan}" } oifname { "${k8sVlan}" } counter accept comment "Allow  LAN to k8s"
              iifname { "${tsIface}" } ip daddr { 192.168.1.156, 10.13.84.181, 10.13.93.50, 10.13.84.104 } counter accept comment "Allow tailscale subnet routing"
              ip saddr 192.168.1.0/24 oifname { "${lanVlan}" } ct state { established, related } counter accept comment "Allow established back to LAN"
              ip saddr 10.13.93.50 ip daddr 10.13.84.100 tcp dport { 22, 3493 } counter accept comment "allow ssh and NUT from home assistant to nas"
              ip saddr 10.13.93.50 ip daddr 192.168.1.5 tcp dport { 443 } counter accept comment "allow HA to talk to CloudKey for Protect events"
              ip saddr 10.13.93.50 ip daddr 10.13.84.100 tcp dport { 5432 } counter accept comment "allow HA to talk to Postgres"
              ip saddr 192.168.1.5 ip daddr 10.13.93.50 ct state { established, related } counter accept comment "Allow established CloudKey back to HA"
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

              # Router DNS IPs - traffic to these doesn't need redirect
              define router_dns = { 192.168.1.1, 10.13.84.1, 10.13.93.1, 10.13.86.1, 10.13.83.1, 10.13.99.1 }

              # Redirect DNS going to external servers through local dnsproxy
              # Uses NFLOG group 2 to keep separate from existing packet logs (group 1)
              # Only intercept VLANs that use local DNS (excludes guest/hazmat which use external)
              iifname { "${lanIface}", "${lanVlan}", "${iotVlan}", "${k8sVlan}" } udp dport 53 ip daddr != $router_dns log group 2 prefix "DNS-REDIRECT: " redirect
              iifname { "${lanIface}", "${lanVlan}", "${iotVlan}", "${k8sVlan}" } tcp dport 53 ip daddr != $router_dns log group 2 prefix "DNS-REDIRECT: " redirect
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
