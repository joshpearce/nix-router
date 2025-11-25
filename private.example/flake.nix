{
  description = "Private configuration for NixOS router (EXAMPLE)";

  outputs = _: {
    nixosModules.default = import ./config.nix;
  };
}
