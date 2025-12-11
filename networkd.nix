{ config, ... }:
let
  internetDnsServer = "9.9.9.9";
  hostName = "nix-router";
  wanIface = "enp1s0";
  lanIface = "enp2s0";
  lanVlan = "lan";
  iotVlan = "iot";
  k8sVlan = "k8s";
  hazmatVlan = "hazmat";
  guestVlan = "guest";

in
{
  config = {
    environment.etc.hostname = {
      text = "${hostName}\n";
    };
    networking.useDHCP = false; # avoid warning: The combination of `systemd.network.enable = true`, `networking.useDHCP = true` and `networking.useNetworkd = false` can cause both networkd and dhcpcd to manage the same interfaces. This can lead to loss of networking. It is recommended you choose only one of networkd (by also enabling `networking.useNetworkd`) or scripting (by disabling `systemd.network.enable`)
    systemd = {
      network = {
        enable = true;
        netdevs = {
          "20-vlan-lan" = {
            netdevConfig = {
              Kind = "vlan";
              Name = "${lanVlan}";
            };
            vlanConfig.Id = 84;
          };
          "20-vlan-iot" = {
            netdevConfig = {
              Kind = "vlan";
              Name = "${iotVlan}";
            };
            vlanConfig.Id = 93;
          };
          "20-vlan-k8s" = {
            netdevConfig = {
              Kind = "vlan";
              Name = "${k8sVlan}";
            };
            vlanConfig.Id = 86;
          };
          "20-vlan-guest" = {
            netdevConfig = {
              Kind = "vlan";
              Name = "${guestVlan}";
            };
            vlanConfig.Id = 83;
          };
          "20-vlan-hazmat" = {
            netdevConfig = {
              Kind = "vlan";
              Name = "${hazmatVlan}";
            };
            vlanConfig.Id = 99;
          };
        };
        networks = {
          "35-unused" = {
            enable = false;
            matchConfig.Name = "enp3s0 enp4s0";
            DHCP = "no";
          };
          "40-enp1s0" = {
            matchConfig.Name = "${wanIface}";
            DHCP = "ipv4";
            dns = [ "" ];
          };
          "40-enp2s0" = {
            matchConfig.Name = "${lanIface}";
            DHCP = "no";
            address = [
              "192.168.1.1/24"
            ];
            vlan = [
              "${lanVlan}"
              "${hazmatVlan}"
              "${iotVlan}"
              "${guestVlan}"
              "${k8sVlan}"
            ];
            networkConfig = {
              DHCPServer = "yes";
            };
            dhcpServerConfig = {
              PoolOffset = 21;
              PoolSize = 200;
              EmitDNS = "yes";
              DNS = "192.168.1.1";
              EmitNTP = "yes";
              NTP = "192.168.1.1";
            };
            dhcpServerStaticLeases = map (lease: {
              Address = lease.address;
              MACAddress = lease.macAddress;
            }) config.private.dhcp.mgmt;
          };
          "50-vlan-lan" = {
            matchConfig.Name = "${lanVlan}";
            address = [ "10.13.84.1/24" ];
            DHCP = "no";
            networkConfig = {
              DHCPServer = "yes";
            };
            dhcpServerConfig = {
              PoolOffset = 21;
              PoolSize = 200;
              EmitDNS = "yes";
              DNS = "10.13.84.1";
              EmitNTP = "yes";
              NTP = "10.13.84.1";
            };
            dhcpServerStaticLeases = map (lease: {
              Address = lease.address;
              MACAddress = lease.macAddress;
            }) config.private.dhcp.lan;
          };
          "50-vlan-iot" = {
            matchConfig.Name = "${iotVlan}";
            address = [ "10.13.93.1/24" ];
            DHCP = "no";
            networkConfig = {
              DHCPServer = "yes";
            };
            dhcpServerConfig = {
              PoolOffset = 21;
              PoolSize = 200;
              EmitDNS = "yes";
              DNS = "10.13.93.1";
              EmitNTP = "yes";
              NTP = "10.13.93.1";
            };
            dhcpServerStaticLeases = map (lease: {
              Address = lease.address;
              MACAddress = lease.macAddress;
            }) config.private.dhcp.iot;
          };
          "50-vlan-guest" = {
            matchConfig.Name = "${guestVlan}";
            address = [ "10.13.83.1/24" ];
            DHCP = "no";
            networkConfig = {
              DHCPServer = "yes";
            };
            dhcpServerConfig = {
              PoolOffset = 21;
              PoolSize = 200;
              EmitDNS = "yes";
              DNS = "${internetDnsServer}";
            };
          };
          "50-vlan-k8s" = {
            matchConfig.Name = "${k8sVlan}";
            address = [ "10.13.86.1/24" ];
            DHCP = "no";
            networkConfig = {
              DHCPServer = "yes";
            };
            dhcpServerConfig = {
              PoolOffset = 2;
              PoolSize = 29;
              EmitDNS = "yes";
              DNS = "10.13.86.1";
              EmitNTP = "yes";
              NTP = "10.13.86.1";
            };
          };
          "50-vlan-hazmat" = {
            matchConfig.Name = "${hazmatVlan}";
            address = [ "10.13.99.1/24" ];
            DHCP = "no";
            networkConfig = {
              DHCPServer = "yes";
            };
            dhcpServerConfig = {
              PoolOffset = 21;
              PoolSize = 200;
              EmitDNS = "yes";
              DNS = "${internetDnsServer}";
            };
          };
        };

      };
    };

  };
}
