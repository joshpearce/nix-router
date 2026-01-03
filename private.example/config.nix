# Private configuration template
#
# Copy this file to private.nix and fill in your values:
#   cp private.nix.example private.nix
#
# private.nix is gitignored and will never be committed.
# If you have the decryption key, you can also run: make decrypt
_: {
  private = {
    user = {
      name = "yourname";
      fullName = "Your Full Name";
      email = "you@example.com";
      sshKeys = [
        # Add your SSH public keys here
        # "ssh-ed25519 AAAA... your-key-comment"
      ];
    };

    # Your primary domain
    domain = "example.com";

    aws = {
      accountId = "123456789012";
      region = "us-east-1";
      route53ZoneId = "Z0123456789ABCDEFGHIJ";
      iamRoleName = "your_domain_mgr";
      sesUsername = "AKIAIOSFODNN7EXAMPLE";
    };

    healthchecks = {
      pingKey = "your-healthchecks-ping-key";
      checkSlug = "router-update-public-ip-in-route53";
    };

    proxyUser = {
      sshKeys = [
        # Add SSH keys for proxy user if needed
      ];
    };

    loki = {
      endpoint = "https://loki.example.com";
    };

    # Extra /etc/hosts entries (IP -> hostnames).
    # Useful when Tailscale MagicDNS isn't available on the router (since it
    # runs its own DNS server), or for any other static host mappings needed.
    hosts = {
      # "100.x.x.x" = [ "myhost.tail-net.ts.net" ];
    };

    # Complete manifest of all known IP assignments by network.
    # - assignment = "dhcp": Device uses DHCP; router provides a static lease (reservation)
    # - assignment = "static": Device has a static IP configured on the device itself
    # Devices with assignment="dhcp" are used by networkd.nix for DHCP reservations.
    ip_manifest = {
      mgmt = [
        # Infrastructure devices (UniFi, IPMI, etc.)
        {
          address = "192.168.1.5";
          macAddress = "aa:bb:cc:dd:ee:00";
          vendor = "Ubiquiti";
          assignment = "dhcp";
          name = "CloudKey2";
        }
        {
          address = "192.168.1.10";
          macAddress = "aa:bb:cc:dd:ee:01";
          vendor = "Ubiquiti";
          assignment = "dhcp";
          name = "unifi-controller";
        }
        {
          address = "192.168.1.20";
          macAddress = "aa:bb:cc:dd:ee:02";
          vendor = "Supermicro";
          assignment = "dhcp";
          name = "NAS-IPMI";
        }
        {
          address = "192.168.1.25";
          macAddress = "aa:bb:cc:dd:ee:03";
          vendor = "Ubiquiti";
          assignment = "dhcp";
          name = "office-ap";
        }
        {
          address = "192.168.1.30";
          macAddress = "aa:bb:cc:dd:ee:04";
          vendor = "Ubiquiti";
          assignment = "dhcp";
          name = "living-room-ap";
        }
      ];
      lan = [
        # Servers and workstations
        {
          address = "10.13.84.50";
          macAddress = "aa:bb:cc:dd:ee:11";
          vendor = "Dell";
          assignment = "dhcp";
          name = "workstation";
        }
        {
          address = "10.13.84.100";
          macAddress = "aa:bb:cc:dd:ee:10";
          vendor = "Supermicro";
          assignment = "dhcp";
          name = "nas";
        }
        {
          address = "10.13.84.104";
          macAddress = "aa:bb:cc:dd:ee:14";
          vendor = "QEMU";
          assignment = "dhcp";
          name = "DESKTOP-7H3GTTS";
        }
        # Client devices (phones, laptops) - name may be empty if unknown
        {
          address = "10.13.84.150";
          macAddress = "aa:bb:cc:dd:ee:12";
          vendor = "Apple";
          assignment = "dhcp";
          name = "macbook";
        }
        {
          address = "10.13.84.151";
          macAddress = "aa:bb:cc:dd:ee:13";
          vendor = "";
          assignment = "dhcp";
          name = "";
        }
      ];
      iot = [
        # Devices with static IPs configured on the device (e.g., ESPHome, Tasmota)
        {
          address = "10.13.93.10";
          macAddress = "aa:bb:cc:dd:ee:30";
          vendor = "Espressif";
          assignment = "static";
          name = "garage-sensor";
        }
        {
          address = "10.13.93.11";
          macAddress = "aa:bb:cc:dd:ee:31";
          vendor = "Espressif";
          assignment = "static";
          name = "";
        }
        {
          address = "10.13.93.12";
          macAddress = "aa:bb:cc:dd:ee:32";
          vendor = "Espressif";
          assignment = "static";
          name = "";
        }
        # Devices using DHCP reservations
        {
          address = "10.13.93.14";
          macAddress = "aa:bb:cc:dd:ee:21";
          vendor = "Brother";
          assignment = "dhcp";
          name = "printer";
        }
        {
          address = "10.13.93.16";
          macAddress = "aa:bb:cc:dd:ee:22";
          vendor = "WiZ";
          assignment = "dhcp";
          name = "wiz1";
        }
        {
          address = "10.13.93.17";
          macAddress = "aa:bb:cc:dd:ee:23";
          vendor = "WiZ";
          assignment = "dhcp";
          name = "wiz2";
        }
        {
          address = "10.13.93.50";
          macAddress = "aa:bb:cc:dd:ee:20";
          vendor = "";
          assignment = "dhcp";
          name = "homeassistant";
        }
        {
          address = "10.13.93.100";
          macAddress = "aa:bb:cc:dd:ee:33";
          vendor = "Philips";
          assignment = "dhcp";
          name = "hue-bridge";
        }
      ];
      hazmat = [
        # Untrusted devices on isolated network
        {
          address = "10.13.99.150";
          macAddress = "aa:bb:cc:dd:ee:40";
          vendor = "";
          assignment = "dhcp";
          name = "";
        }
      ];
    };
  };
}
