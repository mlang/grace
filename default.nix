{ compiler ? "ghc8107" }:

let
  nixpkgs = builtins.fetchTarball {
    url    = "https://github.com/NixOS/nixpkgs/archive/21a3136d25e1652cb32197445e9799e6a5154588.tar.gz";
    sha256 = "145d474g6dngvaiwq2whqdvaq14ba9pc5pvvcz4x8l2bkwbyn3hg";
  };

  overlay = pkgsNew: pkgsOld: {
    haskell = pkgsOld.haskell // {
      packages = pkgsOld.haskell.packages // {
        "${compiler}" = pkgsOld.haskell.packages."${compiler}".override (old: {
          overrides =
            let
              oldOverrides = old.overrides or (_: _: {});

              manualOverrides = haskellPackagesNew: haskellPackagesOld: {
                ghcjs-fetch =
                  pkgsNew.haskell.lib.addBuildDepend
                    (pkgsNew.haskell.lib.doJailbreak
                      (pkgsNew.haskell.lib.dontCheck haskellPackagesOld.ghcjs-fetch)
                    )
                    [ haskellPackagesNew.ghcjs-base ];

                grace =
                  let
                    drv =
                      pkgsNew.haskell.lib.overrideCabal
                        haskellPackagesOld.grace
                        (old: {
                          doCheck = false;

                          src =
                            pkgsNew.lib.cleanSourceWith
                              { inherit (old) src;

                                filter = path: type:
                                      pkgsNew.lib.cleanSourceFilter path type
                                  &&  (!((pkgsNew.lib.hasPrefix "result" (baseNameOf path) && type == "symlink")
                                      || (pkgsNew.lib.hasSuffix ".nix" (baseNameOf path) && type == "regular")
                                      || (pkgsNew.lib.hasSuffix ".md" (baseNameOf path) && type == "regular")
                                      || (baseNameOf path == "cabal.project.local" && type == "regular")
                                      || (baseNameOf path == "dist" && type == "directory")
                                      || (baseNameOf path == "dist-newstyle" && type == "directory")
                                      || (baseNameOf path == "examples" && type == "directory")
                                      || (baseNameOf path == "prelude" && type == "directory")
                                      || (baseNameOf path == "website" && type == "directory")
                                      ));
                              };
                        });

                  in
                    if compiler == "ghcjs"
                    then
                      pkgsNew.haskell.lib.overrideCabal drv
                        (old: {
                          postInstall = (old.postInstall or "") +
                          ''
                          ${pkgsNew.closurecompiler}/bin/closure-compiler $out/bin/try-grace.jsexe/all.js --jscomp_off=checkVars --externs=$out/bin/try-grace.jsexe/all.js.externs > $out/bin/try-grace.jsexe/all.min.js
                          '';
                        })
                    else
                      drv;

                haskeline = haskellPackagesNew.haskeline_0_8_2;

                prettyprinter-ansi-terminal =
                  pkgsNew.haskell.lib.dontCheck haskellPackagesOld.prettyprinter-ansi-terminal;

                vector =
                  pkgsNew.haskell.lib.dontCheck haskellPackagesOld.vector;

              };

              sourceOverrides = pkgsNew.haskell.lib.packageSourceOverrides {
                grace = ./.;
              };

            in
              pkgsNew.lib.fold pkgsNew.lib.composeExtensions oldOverrides
                (   [ sourceOverrides ]
                ++  pkgsNew.lib.optional (compiler == "ghcjs") manualOverrides
                );
        });
      };
    };

    website = pkgsNew.runCommand "try-grace" { } ''
      mkdir -p $out/prelude
      ${pkgsNew.rsync}/bin/rsync --archive ${./website}/ $out
      ${pkgsNew.rsync}/bin/rsync --archive ${./prelude}/ $out/prelude
      chmod u+w $out/js
      cp ${pkgsNew.haskell.packages."${compiler}".grace}/bin/try-grace.jsexe/all.min.js $out/js
    '';
  };

  config.allowBroken = true;

  pkgs = import nixpkgs { inherit config; overlays = [ overlay ]; };

in
  { inherit (pkgs.haskell.packages."${compiler}") grace;

    inherit (pkgs) website;
  }
