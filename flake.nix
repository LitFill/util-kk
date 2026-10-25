{
  description = "LitFill's utilities for Koka";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # koki:inputs:start
    # koki:inputs:end
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      version = "0.1.1";
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system} system);

      # One Koka include directory per dependency. `koki add` writes the
      # lines between the markers below and `koki remove` takes them out;
      # the compiler flags and the editor include list further down are both
      # derived from them, so they cannot drift out of step with each other.
      kokaLibsFor = pkgs: [
        # koki:libs:start
        # koki:libs:end
      ];

      # `--include` flags for the compiler.
      kokaLibArgs = pkgs: builtins.concatStringsSep " " (map (d: "--include=${d}") (kokaLibsFor pkgs));

      # The same list as a `koka.json` `include_dirs` array, which is what
      # editors and the Koka language server read.
      kokaJson =
        pkgs:
        ''{"include_dirs":[${builtins.concatStringsSep "," (map (d: "\"${d}\"") (kokaLibsFor pkgs))}]}'';

      # Shared by the library and the docs, so build artefacts and
      # generated files never leak into either derivation (and never
      # invalidate their hashes).
      srcFor =
        pkgs:
        pkgs.lib.cleanSourceWith {
          src = self;
          filter =
            path: type:
            !(builtins.elem (baseNameOf (toString path)) [
              "result"
              "koka.json"
              ".koka"
              ".koka-build"
              "docs"
            ]);
        };

    in
    {

      packages = forAllSystems (
        pkgs: system: {
          default = pkgs.stdenv.mkDerivation {
            pname = "util";
            inherit version;
            src = srcFor pkgs;

            nativeBuildInputs = [
              pkgs.koka
              pkgs.stdenv.cc
            ];

            buildPhase = ''
              runHook preBuild
              koka -l ${kokaLibArgs pkgs} --output=util --builddir="$PWD/.koka-build" src/util.kk
              runHook postBuild
            '';

            # A Koka library is its source: consumers resolve it with
            # `--include=<includePath>` and compile against these modules.
            installPhase = ''
              runHook preInstall
              install -Dm644 src/util.kk \
                $out/share/koka/${pkgs.koka.version}/util.kk
              runHook postInstall
            '';

            meta = {
              description = "LitFill's utilities for Koka";
              platforms = pkgs.lib.platforms.unix;
            };
          };

          docs = pkgs.stdenv.mkDerivation {
            pname = "util-docs";
            inherit version;
            src = srcFor pkgs;

            nativeBuildInputs = [
              pkgs.koka
            ];

            dontConfigure = true;

            buildPhase = ''
              runHook preBuild

              # The sandbox has a read-only, nonexistent $HOME; give koka
              # somewhere writable in case it wants a cache/config dir.
              export HOME="$TMPDIR"

              mkdir -p docs

              # Invoked through bash explicitly: the build sandbox has no
              # /usr/bin/env for the script's shebang to resolve.
              # KOKA_FLAGS carries the dependency `--include` flags so the
              # docs can be built for modules that import other libraries.
              KOKA=${pkgs.koka}/bin/koka \
              KOKA_FLAGS="${kokaLibArgs pkgs}" \
                bash scripts/build-docs.sh docs

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              test -n "$(ls -A docs)" || { echo "docs/ is empty" >&2; exit 1; }
              mkdir -p "$out"
              cp -r docs/. "$out/"
              runHook postInstall
            '';

            # Cheap to build and not worth a remote builder round-trip.
            preferLocalBuild = true;

            meta = {
              description = "API reference for LitFill's Koka utilities";
              platforms = pkgs.lib.platforms.unix;
            };
          };
        }
      );
      apps = forAllSystems (
        pkgs: system: {
          docs = {
            type = "app";
            program = "${
              pkgs.writeShellApplication {
                name = "gen-docs";
                runtimeInputs = [
                  pkgs.koka
                  pkgs.git
                ];
                text = ''
                  # Selalu tulis ke <root repo>/docs, dari subfolder mana pun
                  # perintah ini dijalankan.
                  cd "$(git rev-parse --show-toplevel)"
                  mkdir -p docs

                  KOKA=${pkgs.koka}/bin/koka \
                  KOKA_FLAGS="${kokaLibArgs pkgs}" \
                    bash scripts/build-docs.sh docs
                '';
              }
            }/bin/gen-docs";
          };
        }
      );

      # How a consuming flake reaches this library. `koki add` writes
      # `self.inputs.<input>.kokaLibraries.<system>.util.includePath`
      # when this flake is added as a dependency.
      kokaLibraries = forAllSystems (
        pkgs: system: {
          util = {
            path = self.packages.${system}.default;
            includePath = "${self.packages.${system}.default}/share/koka/${pkgs.koka.version}";
            version = pkgs.koka.version;
            libVersion = self.packages.${system}.default.version;
          };
        }
      );

      devShells = forAllSystems (
        pkgs: system: {
          default = pkgs.mkShell {
            packages = [ pkgs.koka ];
            shellHook = "printf '%s\\n' '${kokaJson pkgs}' > \"$PWD/koka.json\"";
          };
        }
      );

      checks = forAllSystems (
        pkgs: system: {
          build = self.packages.${system}.default;
          docs = self.packages.${system}.docs;
        }
      );
    };
}
