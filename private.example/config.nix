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

    dhcp = {
      mgmt = [
        {
          name = "unifi-controller";
          address = "192.168.1.10";
          macAddress = "aa:bb:cc:dd:ee:01";
        }
        {
          name = "ipmi";
          address = "192.168.1.20";
          macAddress = "aa:bb:cc:dd:ee:02";
        }
      ];
      lan = [
        {
          name = "nas";
          address = "10.13.84.100";
          macAddress = "aa:bb:cc:dd:ee:10";
        }
        {
          name = "workstation";
          address = "10.13.84.50";
          macAddress = "aa:bb:cc:dd:ee:11";
        }
      ];
      iot = [
        {
          name = "homeassistant";
          address = "10.13.93.50";
          macAddress = "aa:bb:cc:dd:ee:20";
        }
        {
          name = "printer";
          address = "10.13.93.14";
          macAddress = "aa:bb:cc:dd:ee:21";
        }
        {
          name = "smart-plug";
          address = "10.13.93.100";
          macAddress = "aa:bb:cc:dd:ee:22";
        }
      ];
    };
  };
}
