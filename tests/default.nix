# Test aggregator - imports all test modules
{
  lib,
  pkgs,
  vectorSettings,
}:
{
  lib-tests = import ./lib-tests.nix { inherit lib pkgs; };
  shell-tests = import ./shell-tests.nix { inherit pkgs; };
  firewall-tests = import ./firewall-tests.nix { inherit pkgs; };
  dns-dhcp-tests = import ./dns-dhcp-tests.nix { inherit lib pkgs; };
  router-health-tests = import ./router-health-tests.nix { inherit pkgs; };
  vector-redirect-tests = import ./vector-redirect-tests.nix {
    inherit pkgs vectorSettings;
  };
}
