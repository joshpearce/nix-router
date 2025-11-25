# Shell script tests for is-private-ip utility
{ pkgs }:
let
  shellUtils = pkgs.callPackage ../packages/shell-utils/shell-utils.nix { };
in
pkgs.runCommand "shell-tests" { buildInputs = [ shellUtils ]; } ''
  echo "Testing is-private-ip..."

  # Should return 0 (true) for private IPs in 10.0.0.0/8 range
  is-private-ip 10.0.0.1 || { echo "FAIL: 10.0.0.1 should be private"; exit 1; }
  is-private-ip 10.255.255.255 || { echo "FAIL: 10.255.255.255 should be private"; exit 1; }
  is-private-ip 10.13.84.100 || { echo "FAIL: 10.13.84.100 should be private"; exit 1; }

  # Should return 0 (true) for private IPs in 172.16.0.0/12 range
  is-private-ip 172.16.0.1 || { echo "FAIL: 172.16.0.1 should be private"; exit 1; }
  is-private-ip 172.31.255.255 || { echo "FAIL: 172.31.255.255 should be private"; exit 1; }

  # Should return 0 (true) for private IPs in 192.168.0.0/16 range
  is-private-ip 192.168.1.1 || { echo "FAIL: 192.168.1.1 should be private"; exit 1; }
  is-private-ip 192.168.255.255 || { echo "FAIL: 192.168.255.255 should be private"; exit 1; }

  # Should return 1 (false) for public IPs
  ! is-private-ip 8.8.8.8 || { echo "FAIL: 8.8.8.8 should be public"; exit 1; }
  ! is-private-ip 1.1.1.1 || { echo "FAIL: 1.1.1.1 should be public"; exit 1; }

  # Should return 1 (false) for IPs outside 172.16-31 range
  ! is-private-ip 172.32.0.1 || { echo "FAIL: 172.32.0.1 should be public"; exit 1; }
  ! is-private-ip 172.15.255.255 || { echo "FAIL: 172.15.255.255 should be public"; exit 1; }

  # Should return 1 (false) for IPs outside 192.168 range
  ! is-private-ip 192.169.1.1 || { echo "FAIL: 192.169.1.1 should be public"; exit 1; }

  # Invalid input should return 1 (false)
  ! is-private-ip "invalid" || { echo "FAIL: invalid input should return 1"; exit 1; }
  ! is-private-ip "" || { echo "FAIL: empty input should return 1"; exit 1; }
  ! is-private-ip "10.0.0" || { echo "FAIL: incomplete IP should return 1"; exit 1; }
  ! is-private-ip "10.0.0.0.0" || { echo "FAIL: too many octets should return 1"; exit 1; }

  echo "All shell tests passed!"
  touch $out
''
