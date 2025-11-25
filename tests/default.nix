# Test aggregator - imports all test modules
{ lib, pkgs }:
{
  lib-tests = import ./lib-tests.nix { inherit lib pkgs; };
  shell-tests = import ./shell-tests.nix { inherit pkgs; };
  firewall-tests = import ./firewall-tests.nix { inherit pkgs; };
  dns-dhcp-tests = import ./dns-dhcp-tests.nix { inherit lib pkgs; };
}
