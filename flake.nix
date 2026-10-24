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
      # The router only consumes Linux outputs. Current unstable no longer
      # evaluates x86_64-darwin, which flake-utils otherwise includes by default.
      inputs.flake-utils.inputs.systems.follows = "linux-systems";
    };

    linux-systems.url = "github:nix-systems/x86_64-linux";

    # Private configuration - override this with your local private/ directory
    # Build with: nixos-rebuild switch --flake .#router --override-input private path:./private
    private = {
      url = "path:./private.example";
      flake = true;
    };
  };

  outputs =
    flakes@{
      self,
      nixpkgs,
      agenix,
      vscode-server,
      private,
      ...
    }:
    let
      system = "x86_64-linux";

      # Big cmake upgrade with lots of issues. Need to try removing this later.
      # https://github.com/NixOS/nixpkgs/issues/445447
      overlay-router = _final: prev: {
        rtrlib = prev.rtrlib.overrideAttrs (old: {
          cmakeFlags = (old.cmakeFlags or [ ]) ++ [
            "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
          ];
        });

        # Vector 0.59 denies deprecation warnings, while Rust 1.99 renamed
        # AtomicU64::fetch_update to try_update without changing its behavior.
        vector = prev.vector.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace lib/vector-common/src/atomic.rs \
              --replace-fail ".fetch_update(" ".try_update("
          '';
        });
      };

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ overlay-router ];
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
                overlays = [ overlay-router ];
              };
            }
          )

          ./default.nix
        ];
      };

      checks.${system} = import ./tests {
        inherit (nixpkgs) lib;
        inherit pkgs;
        vectorSettings = self.nixosConfigurations.router.config.services.vector2.settings;
      };
    };
}
