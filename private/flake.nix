{
  description = "Private configuration for NixOS router";

  outputs = _: {
    nixosModules.default = import ./config.nix;
  };
}
