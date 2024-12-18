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
            ghc982 = prev.haskell.packages.ghc982.override (old: {
              overrides = prev.lib.composeExtensions (old.overrides or (_: _: { })) (
                hfinal: hprev: {
                  skeletest = hprev.skeletest.overrideAttrs (old: {
                    meta = old.meta // { broken = false; };
                  });
                  Diff = hfinal.callHackage "Diff" "0.5" { };
                  http2 = hprev.http2.overrideAttrs (_: {
                    doCheck = !prev.stdenv.buildPlatform.isDarwin;
                  });
                }
              );
            });
            ghc966 = prev.haskell.packages.ghc966.override (old: {
              overrides = prev.lib.composeExtensions (old.overrides or (_: _: { })) (
                hfinal: hprev: {
                  attoparsec-aeson = hfinal.callHackage "attoparsec-aeson" "2.2.0.0" { };
                  skeletest = hprev.skeletest.overrideAttrs (old: {
                    meta = old.meta // { broken = false; };
                  });
                  Diff = hfinal.callHackage "Diff" "0.5" { };
                  aeson = hfinal.callHackage "aeson" "2.2.2.0" { };
                  http2 = hprev.http2.overrideAttrs (_: {
                    doCheck = !prev.stdenv.buildPlatform.isDarwin;
                  });
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
        };

        pkgsOverlayed = import inputs.nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };

        # Define GHC versions list
        ghcVersions = [ "966" "982" ];

        # Create an attrset of GHC packages
        ghcPkgs = builtins.listToAttrs (map
          (version: {
            name = "ghc${version}";
            value = pkgsOverlayed.haskell.packages."ghc${version}";
          })
          ghcVersions);

        example-src = nix-filter.lib {
          root = ./example;
          include = [
            (nix-filter.lib.inDirectory "app")
            ./example/example.cabal
            ./example/cabal.project
            ./example/LICENSE
          ];
        };

        shellCommon = version: {
          inherit (self.checks.${system}.pre-commit-check) shellHook;
          buildInputs = with pkgs.haskell.packages."ghc${version}"; [
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

        # Create examples for each GHC version
        examples = builtins.listToAttrs (map
          (version: {
            name = "ghc${version}-example";
            value = ghcPkgs."ghc${version}".callCabal2nix "example" example-src { };
          })
          ghcVersions);

      in
      {
        checks = {
          pre-commit-check = git-hooks.lib.${system}.run {
            src = web-view-src;
            hooks = {
              hpack.enable = true;
              nixpkgs-fmt.enable = true;
              flake-checker = {
                enable = true;
                args = [ "--no-telemetry" ];
              };
              check-merge-conflicts.enable = true;
            };
          };
        } // builtins.listToAttrs (
          # Generate checks
          builtins.concatMap
            (version: [
              {
                name = "ghc${version}-check";
                value = self.packages.${system}."ghc${version}-web-view";
              }
              {
                name = "ghc${version}-check-example";
                value = pkgs.haskell.lib.justStaticExecutables examples."ghc${version}-example";
              }
            ])
            ghcVersions
        );

        apps = {
          default = self.apps.${system}.ghc966-example;
        } // builtins.listToAttrs (
          # Generate apps
          map
            (version: {
              name = "ghc${version}-example";
              value = {
                type = "app";
                program = "${pkgs.haskell.lib.justStaticExecutables examples."ghc${version}-example"}/bin/example";
              };
            })
            ghcVersions
        );

        packages = {
          default = self.packages.${system}.ghc982-web-view;
        } // builtins.listToAttrs (
          # Generate packages
          map
            (version: {
              name = "ghc${version}-web-view";
              value = ghcPkgs."ghc${version}".web-view;
            })
            ghcVersions
        );

        devShells = {
          default = self.devShells.${system}.ghc982-web-view;
        } // builtins.listToAttrs (
          # Generate devShells
          builtins.concatMap
            (version: [
              {
                name = "ghc${version}-web-view";
                value = ghcPkgs."ghc${version}".shellFor (
                  shellCommon version // { packages = p: [ p.web-view ]; }
                );
              }
              {
                name = "ghc${version}-example";
                value = ghcPkgs."ghc${version}".shellFor (
                  shellCommon version // { packages = _: [ examples."ghc${version}-example" ]; }
                );
              }
            ])
            ghcVersions
        );
      }
    );
}
