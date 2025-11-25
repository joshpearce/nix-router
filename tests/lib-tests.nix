# Unit tests for router library functions
{ lib, pkgs }:
let
  routerLib = import ./lib.nix { inherit lib; };

  tests = {
    # vlanToSubnet tests
    testVlanToSubnetLan = {
      expr = routerLib.vlanToSubnet 84;
      expected = "10.13.84.0/24";
    };
    testVlanToSubnetIot = {
      expr = routerLib.vlanToSubnet 93;
      expected = "10.13.93.0/24";
    };
    testVlanToSubnetK8s = {
      expr = routerLib.vlanToSubnet 86;
      expected = "10.13.86.0/24";
    };
    testVlanToSubnetGuest = {
      expr = routerLib.vlanToSubnet 83;
      expected = "10.13.83.0/24";
    };
    testVlanToSubnetHazmat = {
      expr = routerLib.vlanToSubnet 99;
      expected = "10.13.99.0/24";
    };

    # vlanToGateway tests
    testVlanToGatewayLan = {
      expr = routerLib.vlanToGateway 84;
      expected = "10.13.84.1";
    };
    testVlanToGatewayIot = {
      expr = routerLib.vlanToGateway 93;
      expected = "10.13.93.1";
    };

    # ipInVlan tests
    testIpInVlanTrue = {
      expr = routerLib.ipInVlan "10.13.84.100" 84;
      expected = true;
    };
    testIpInVlanFalse = {
      expr = routerLib.ipInVlan "10.13.93.100" 84;
      expected = false;
    };
    testIpInVlanGateway = {
      expr = routerLib.ipInVlan "10.13.84.1" 84;
      expected = true;
    };
    testIpInVlanWrongNetwork = {
      expr = routerLib.ipInVlan "192.168.1.100" 84;
      expected = false;
    };

    # isPrivateIp tests - 10.0.0.0/8 range
    testIsPrivateIp10 = {
      expr = routerLib.isPrivateIp "10.0.0.1";
      expected = true;
    };
    testIsPrivateIp10Max = {
      expr = routerLib.isPrivateIp "10.255.255.255";
      expected = true;
    };
    testIsPrivateIpLan = {
      expr = routerLib.isPrivateIp "10.13.84.100";
      expected = true;
    };

    # isPrivateIp tests - 172.16.0.0/12 range
    testIsPrivateIp172Min = {
      expr = routerLib.isPrivateIp "172.16.0.1";
      expected = true;
    };
    testIsPrivateIp172Max = {
      expr = routerLib.isPrivateIp "172.31.255.255";
      expected = true;
    };
    testIsPrivateIp172Below = {
      expr = routerLib.isPrivateIp "172.15.255.255";
      expected = false;
    };
    testIsPrivateIp172Above = {
      expr = routerLib.isPrivateIp "172.32.0.1";
      expected = false;
    };

    # isPrivateIp tests - 192.168.0.0/16 range
    testIsPrivateIp192 = {
      expr = routerLib.isPrivateIp "192.168.1.1";
      expected = true;
    };
    testIsPrivateIp192Max = {
      expr = routerLib.isPrivateIp "192.168.255.255";
      expected = true;
    };
    testIsPrivateIp192Wrong = {
      expr = routerLib.isPrivateIp "192.169.1.1";
      expected = false;
    };

    # isPrivateIp tests - public IPs
    testIsPrivateIpPublic1 = {
      expr = routerLib.isPrivateIp "8.8.8.8";
      expected = false;
    };
    testIsPrivateIpPublic2 = {
      expr = routerLib.isPrivateIp "1.1.1.1";
      expected = false;
    };

    # validateDhcpPool tests
    testValidateDhcpPoolValid = {
      expr =
        (routerLib.validateDhcpPool {
          poolOffset = 21;
          poolSize = 200;
        }).valid;
      expected = true;
    };
    testValidateDhcpPoolTooLow = {
      expr =
        (routerLib.validateDhcpPool {
          poolOffset = 10;
          poolSize = 200;
        }).valid;
      expected = false;
    };
    testValidateDhcpPoolTooHigh = {
      expr =
        (routerLib.validateDhcpPool {
          poolOffset = 100;
          poolSize = 200;
        }).valid;
      expected = false;
    };
    testValidateDhcpPoolK8s = {
      expr =
        (routerLib.validateDhcpPool {
          poolOffset = 2;
          poolSize = 29;
          reservedEnd = 1;
        }).valid;
      expected = true;
    };

    # validateStaticLease tests
    testValidateStaticLeaseValid = {
      expr =
        (routerLib.validateStaticLease {
          address = "10.13.84.100";
          vlanId = 84;
        }).valid;
      expected = true;
    };
    testValidateStaticLeaseInvalid = {
      expr =
        (routerLib.validateStaticLease {
          address = "10.13.93.100";
          vlanId = 84;
        }).valid;
      expected = false;
    };
  };

  results = lib.debug.runTests tests;
  testCount = builtins.length (builtins.attrNames tests);
in
pkgs.runCommand "lib-tests" { } ''
  ${
    if results == [ ] then
      ''
        echo "All ${toString testCount} tests passed"
        touch $out
      ''
    else
      ''
        echo "Test failures:"
        echo "${builtins.toJSON results}"
        exit 1
      ''
  }
''
