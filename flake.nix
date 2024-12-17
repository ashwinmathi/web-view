{
  description = "web-view";

  inputs = {
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nix-filter.url = "github:numtide/nix-filter/main";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    inputs@{ self
    , flake-utils
    , nix-filter
    , git-hooks
    , ...
    }:
    let
      web-view-src = nix-filter.lib {
        root = ./.;
        include = [
          (nix-filter.lib.inDirectory "src")
          (nix-filter.lib.inDirectory "embed")
          (nix-filter.lib.inDirectory "test")
          ./README.md
          ./CHANGELOG.md
          ./LICENSE
          ./web-view.cabal
          ./cabal.project
          ./package.yaml
          ./fourmolu.yaml
        ];
      };

      overlay = final: prev: {
        # see https://github.com/NixOS/nixpkgs/issues/83098
        cabal2nix-unwrapped = prev.haskell.lib.justStaticExecutables prev.haskell.packages.ghc94.cabal2nix;
        haskell = prev.haskell // {
          packageOverrides = prev.lib.composeExtensions prev.haskell.packageOverrides (hfinal: hprev: {
            web-view = hfinal.callCabal2nix "web-view" web-view-src { };
          });
          packages = prev.haskell.packages // {
            ghc966 = prev.haskell.packages.ghc966.override (old: {
              overrides = prev.lib.composeExtensions (old.overrides or (_: _: { })) (
                hfinal: hprev: {
                  attoparsec-aeson = hfinal.callHackage "attoparsec-aeson" "2.2.0.0" { };
                  skeletest = hprev.skeletest.overrideAttrs (old: {
                    meta = old.meta // { broken = false; };
                  });
                  Diff = hfinal.callHackage "Diff" "0.5" { };
                  aeson = hfinal.callHackage "aeson" "2.2.2.0" { };
                }
              );
            });
          };
        };
      };
    in
    {
      overlays.default = overlay;
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import inputs.nixpkgs {
          inherit system;
          # overlays = [ self.overlays.default ];
        };

        example-src = nix-filter.lib {
          root = ./example;
          include = [
            (nix-filter.lib.inDirectory "app")
            ./example/example.cabal
            ./example/cabal.project
          ];
        };

        myHaskellPackages = (import inputs.nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        }).haskell.packages.ghc966.override (old: {
          overrides = pkgs.lib.composeExtensions (old.overrides or (_: _: { })) (
            hfinal: hprev: {
              # attoparsec-aeson = hfinal.callHackage "attoparsec-aeson" "2.2.0.0" { };
              # skeletest = hprev.skeletest.overrideAttrs (old: {
              #   meta = old.meta // { broken = false; };
              # });
              # Diff = hfinal.callHackage "Diff" "0.5" { };
              # aeson = hfinal.callHackage "aeson" "2.2.2.0" { };
            }
          );
        });

        shellCommon = {
          inherit (self.checks.${system}.pre-commit-check) shellHook;
          # don't use the modified package set to build dev tools
          buildInputs = with pkgs.haskellPackages; [
            cabal-install
            haskell-language-server
            fast-tags
            ghcid
            fourmolu
            pkgs.hpack
          ];
          withHoogle = true;
          doBenchmark = true;
          CABAL_CONFIG = "/dev/null";
        };

      in
      {
        checks = {
          pre-commit-check = git-hooks.lib.${system}.run {
            src = web-view-src;
            hooks = {
              # hlint.enable = true;
              # hpack.enable = true;
              # fourmolu.enable = true;
              nixpkgs-fmt.enable = true;
              flake-checker = {
                enable = true;
                args = [ "--no-telemetry" ];
              };
              check-merge-conflicts.enable = true;
            };
          };
        };

        packages = {
          default = self.packages.${system}.web-view;
          web-view = myHaskellPackages.web-view;
        };

        devShells = {
          default = self.devShells.${system}.web-view;
          web-view = myHaskellPackages.shellFor (
            shellCommon // { packages = p: [ p.web-view ]; }
          );
          example = myHaskellPackages.shellFor (
            shellCommon
            // {
              packages = _: [
                (myHaskellPackages.callCabal2nix "example" example-src { })
              ];
            }
          );
        };
      }
    );
}
