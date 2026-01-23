# Firewall nftables validation tests
# Note: nft -c requires netlink which isn't available in the Nix sandbox,
# so we validate structure with grep instead of full syntax check
{ pkgs }:
let
  mockConfig = {
    private.ip_manifest = {
      mgmt = [
        {
          address = "192.168.1.5";
          name = "cloudkey2";
          macAddress = "";
          vendor = "";
          assignment = "dhcp";
        }
        {
          address = "192.168.1.156";
          name = "nas-ipmi";
          macAddress = "";
          vendor = "";
          assignment = "dhcp";
        }
      ];
      lan = [
        {
          address = "10.13.84.100";
          name = "nas";
          macAddress = "";
          vendor = "";
          assignment = "dhcp";
        }
        {
          address = "10.13.84.104";
          name = "windows-vm1";
          macAddress = "";
          vendor = "";
          assignment = "dhcp";
        }
      ];
      iot = [
        {
          address = "10.13.93.50";
          name = "homeassistant";
          macAddress = "";
          vendor = "";
          assignment = "dhcp";
        }
        {
          address = "10.13.93.14";
          name = "printer";
          macAddress = "";
          vendor = "";
          assignment = "dhcp";
        }
        {
          address = "10.13.93.16";
          name = "wiz-dimmable-white-1";
          macAddress = "";
          vendor = "";
          assignment = "dhcp";
        }
        {
          address = "10.13.93.17";
          name = "wiz-dimmable-white-2";
          macAddress = "";
          vendor = "";
          assignment = "dhcp";
        }
      ];
      hazmat = [ ];
    };
  };
  firewallConfig = import ../firewall.nix { config = mockConfig; };
  inherit (firewallConfig.config.networking.nftables) ruleset;
in
pkgs.runCommand "firewall-tests" { } ''
  echo "Validating nftables ruleset structure..."

  # Write ruleset to a file for grep to parse
  cat > ruleset.nft << 'RULESET'
  ${ruleset}
  RULESET

  # Check for required tables
  echo "Checking required tables..."
  grep -q "table ip filter" ruleset.nft || { echo "FAIL: Missing ip filter table"; exit 1; }
  grep -q "table ip nat" ruleset.nft || { echo "FAIL: Missing ip nat table"; exit 1; }
  grep -q "table ip6 filter" ruleset.nft || { echo "FAIL: Missing ip6 filter table"; exit 1; }
  echo "  Required tables present"

  # Check for required chains in ip filter table
  echo "Checking required chains..."
  grep -q "chain input" ruleset.nft || { echo "FAIL: Missing input chain"; exit 1; }
  grep -q "chain forward" ruleset.nft || { echo "FAIL: Missing forward chain"; exit 1; }
  grep -q "chain postrouting" ruleset.nft || { echo "FAIL: Missing postrouting chain"; exit 1; }
  echo "  Required chains present"

  # Check for drop policies (security requirement)
  echo "Checking security policies..."
  grep -q "policy drop" ruleset.nft || { echo "FAIL: Missing drop policy"; exit 1; }
  echo "  Drop policies present"

  # Check NAT masquerade exists for WAN
  echo "Checking NAT configuration..."
  grep -q "masquerade" ruleset.nft || { echo "FAIL: Missing masquerade for NAT"; exit 1; }
  echo "  NAT masquerade configured"

  # Check tailscale chains exist
  echo "Checking Tailscale integration..."
  grep -q "ts-input" ruleset.nft || { echo "FAIL: Missing ts-input chain"; exit 1; }
  grep -q "ts-forward" ruleset.nft || { echo "FAIL: Missing ts-forward chain"; exit 1; }
  grep -q "ts-postrouting" ruleset.nft || { echo "FAIL: Missing ts-postrouting chain"; exit 1; }
  echo "  Tailscale chains present"

  # Check loopback is accepted
  echo "Checking loopback acceptance..."
  grep -q "iif lo accept" ruleset.nft || { echo "FAIL: Missing loopback accept rule"; exit 1; }
  echo "  Loopback accepted"

  # Check WAN interface is configured
  echo "Checking WAN interface..."
  grep -q 'iifname.*enp1s0' ruleset.nft || { echo "FAIL: Missing WAN interface rules"; exit 1; }
  echo "  WAN interface configured"

  echo ""
  echo "Firewall validation passed!"
  touch $out
''
