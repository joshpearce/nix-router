# DNS/DHCP configuration validation tests
{ lib, pkgs }:
let
  routerLib = import ./lib.nix { inherit lib; };

  # VLAN configuration to test (matches networkd.nix)
  vlans = {
    lan = {
      id = 84;
      gateway = "10.13.84.1";
      poolOffset = 21;
      poolSize = 200;
    };
    iot = {
      id = 93;
      gateway = "10.13.93.1";
      poolOffset = 21;
      poolSize = 200;
    };
    k8s = {
      id = 86;
      gateway = "10.13.86.1";
      poolOffset = 2;
      poolSize = 29;
    };
    guest = {
      id = 83;
      gateway = "10.13.83.1";
      poolOffset = 21;
      poolSize = 200;
    };
    hazmat = {
      id = 99;
      gateway = "10.13.99.1";
      poolOffset = 21;
      poolSize = 200;
    };
  };

  # Tests for VLAN subnet consistency
  vlanSubnetTests = lib.mapAttrsToList (
    name: vlan:
    let
      expectedSubnet = "10.13.${toString vlan.id}.0/24";
      computedSubnet = routerLib.vlanToSubnet vlan.id;
      expectedGateway = "10.13.${toString vlan.id}.1";
    in
    {
      name = "vlan-${name}";
      valid = computedSubnet == expectedSubnet && vlan.gateway == expectedGateway;
      expected = {
        subnet = expectedSubnet;
        gateway = expectedGateway;
      };
      actual = {
        subnet = computedSubnet;
        inherit (vlan) gateway;
      };
    }
  ) vlans;

  # Tests for DHCP pool validity
  dhcpPoolTests = lib.mapAttrsToList (
    name: vlan:
    let
      # k8s has different reserved range
      reservedEnd = if name == "k8s" then 1 else 20;
      result = routerLib.validateDhcpPool {
        inherit (vlan) poolOffset poolSize;
        inherit reservedEnd;
      };
    in
    {
      name = "dhcp-pool-${name}";
      inherit (result)
        valid
        poolStart
        poolEnd
        error
        ;
    }
  ) vlans;

  allTests = vlanSubnetTests ++ dhcpPoolTests;
  failedTests = builtins.filter (t: !t.valid) allTests;
in
pkgs.runCommand "dns-dhcp-tests" { } ''
  echo "Validating DNS/DHCP configuration..."
  echo ""

  ${
    if failedTests == [ ] then
      ''
        echo "VLAN subnet tests:"
        ${lib.concatMapStrings (t: ''
          echo "  ${t.name}: OK"
        '') vlanSubnetTests}

        echo ""
        echo "DHCP pool tests:"
        ${lib.concatMapStrings (t: ''
          echo "  ${t.name}: OK (pool ${toString t.poolStart}-${toString t.poolEnd})"
        '') dhcpPoolTests}

        echo ""
        echo "All ${toString (builtins.length allTests)} DNS/DHCP tests passed!"
        touch $out
      ''
    else
      ''
        echo "Test failures:"
        ${lib.concatMapStrings (t: ''
          echo "  FAIL: ${t.name}"
          ${
            if t ? error && t.error != null then
              ''
                echo "    Error: ${t.error}"
              ''
            else
              ''
                echo "    Expected: ${builtins.toJSON t.expected}"
                echo "    Actual: ${builtins.toJSON t.actual}"
              ''
          }
        '') failedTests}
        exit 1
      ''
  }
''
