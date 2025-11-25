{
  description = "Router NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vscode-server = {
      url = "github:joshpearce/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Private configuration - override this with your local private/ directory
    # Build with: nixos-rebuild switch --flake .#router --override-input private path:./private
    private = {
      url = "path:./private.example";
      flake = true;
    };
  };

  outputs =
    {
      nixpkgs,
      agenix,
      vscode-server,
      private,
      ...
    }@flakes:
    let
      system = "x86_64-linux";

      # Big cmake upgrade with lots of issues. Need to try removing this later.
      # https://github.com/NixOS/nixpkgs/issues/445447
      overlay-rtrlib = _final: prev: {
        rtrlib = prev.rtrlib.overrideAttrs (old: {
          cmakeFlags = (old.cmakeFlags or [ ]) ++ [
            "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
          ];
        });
      };

    in
    {
      nixosConfigurations.router = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = flakes // {
          inherit system;
        };
        modules = [
          agenix.nixosModules.default
          vscode-server.nixosModules.default
          private.nixosModules.default

          (
            { pkgs, ... }:
            {
              nix = {
                extraOptions = "experimental-features = nix-command flakes";
                package = pkgs.nixVersions.stable;
                registry.nixpkgs.flake = nixpkgs;
              };
              nixpkgs = {
                config.allowUnfree = true;
                overlays = [ overlay-rtrlib ];
              };
            }
          )

          ./default.nix
        ];
      };

      checks.${system} = import ./tests {
        inherit (nixpkgs) lib;
        pkgs = nixpkgs.legacyPackages.${system};
      };
    };
}
