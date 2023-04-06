{
  description = "Chainweb";

  inputs = {
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, haskellNix }:
    flake-utils.lib.eachSystem
      [ "x86_64-linux" "x86_64-darwin"
        "aarch64-linux" "aarch64-darwin" ] (system:
    let
      pkgs = import nixpkgs {
        inherit system overlays;
        inherit (haskellNix) config;
      };
      flake = pkgs.chainweb.flake {
      };
      overlays = [ haskellNix.overlay
        (final: prev: {
          chainweb =
            final.haskell-nix.project' {
              src = ./.;
              compiler-nix-name = "ghc961";
              shell.tools = {
                cabal = {};
                # hlint = {};
              };
              shell.buildInputs = with pkgs; [
                zlib
                gflags
                snappy
                openssl
                pkgconfig
              ];
            };
        })
      ];
    in flake // {
      packages.default = flake.packages."chainweb:exe:chainweb-node";
    });

    # --- Flake Local Nix Configuration ----------------------------
    nixConfig = {
      # This sets the flake to use the IOG nix cache.
      extra-substituters = [
        "https://cache.iog.io"
        "http://nixcache.kadena.io"
        "https://nixcache.chainweb.com"
      ];
      extra-trusted-public-keys = [
        "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
        "kadena-cache.local-1:8wj8JW8V9tmc5bgNNyPM18DYNA1ws3X/MChXh1AQy/Q="
        "nixcache.chainweb.com:FVN503ABX9F8x8K0ptnc99XEz5SaA4Sks6kNcZn2pBY="
      ];
      allow-import-from-derivation = "true";
    };
}
