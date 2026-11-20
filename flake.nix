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
      inherit (nixpkgs.lib) genAttrs;
      inherit (builtins) concatStringsSep elem match;

      version = "0.2.0";
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: genAttrs systems (system: f nixpkgs.legacyPackages.${system} system);

      # One Koka include directory per dependency. `koki add` writes the
      # lines between the markers below and `koki remove` takes them out;
      # the compiler flags and the editor include list further down are both
      # derived from them, so they cannot drift out of step with each other.
      kokaLibsFor = pkgs: [
        # koki:libs:start
        # koki:libs:end
      ];

      # `--include` flags for the compiler.
      kokaLibArgs = pkgs: kokaLibsFor pkgs |> map (d: "--include=${d}") |> concatStringsSep " ";

      # The same list as a `koka.json` `include_dirs` array, which is what
      # editors and the Koka language server read.
      kokaJson =
        pkgs:
        let
          dirs = kokaLibsFor pkgs |> map (d: "\"${d}\"") |> concatStringsSep ",";
        in
        ''{"include_dirs":[${dirs}]}'';

      # The modules the package installs. Both the build and the install step
      # derive their file list from this one place, so they cannot drift.
      modules = [
        "util.kk"
        "utils/het-cmp.kk"
        "utils/state.kk"
        "utils/reader.kk"
        "utils/exit.kk"
      ];

      # The same modules as paths from the repository root, which is what the
      # docs generator takes.
      docModules = map (m: "src/${m}") modules;

      # Shared by the library and the docs, so build artefacts and
      # generated files never leak into either derivation (and never
      # invalidate their hashes).
      srcFor =
        pkgs:
        let
          inherit (pkgs.lib) cleanSourceWith;
        in
        cleanSourceWith {
          src = self;
          filter =
            path: type:
            let
              name = baseNameOf (path |> toString);
            in
            !(
              elem name [
                "result"
                "koka.json"
                ".koka"
                ".koka-build"
                "docs"
              ]
              || match "result-.*" name != null
            );
        };

    in
    {

      packages = forAllSystems (
        pkgs: system:
        let
          inherit (pkgs.stdenv) mkDerivation;
          inherit (pkgs.lib) concatStringsSep licenses platforms;
        in
        {
          default = mkDerivation {
            pname = "util";
            inherit version;
            src = srcFor pkgs;

            nativeBuildInputs = [
              pkgs.koka
              pkgs.stdenv.cc
            ];

            buildPhase = ''
              runHook preBuild
                export HOME="$TMPDIR"
                koka -l ${kokaLibArgs pkgs} --output=util --builddir="$PWD/.koka-build" ${
                  modules |> map (m: "src/${m}") |> concatStringsSep " "
                }
              runHook postBuild
            '';

            # A Koka library is its source: consumers resolve it with
            # `--include=<includePath>` and compile against these modules.
            installPhase =
              let
                installFor = module: /* bash */ "install -Dm644 src/${module} $out/share/koka/${pkgs.koka.version}/${module}";
              in
              /* bash */ ''
                runHook preInstall
                  ${map installFor modules |> concatStringsSep "\n"}
                runHook postInstall
              '';

            meta = {
              description = "LitFill's utilities for Koka";
              license = licenses.mit;
              platforms = platforms.unix;
            };
          };

          docs = mkDerivation {
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

              # Invoked through bash explicitly: the build sandbox has no
              # /usr/bin/env for the script's shebang to resolve.
              # KOKA_FLAGS carries the dependency `--include` flags so the
              # docs can be built for modules that import other libraries.
              KOKA=${pkgs.koka}/bin/koka \
              KOKA_FLAGS="${kokaLibArgs pkgs}" \
                bash scripts/build-docs.sh docs ${concatStringsSep " " docModules}

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
              license = licenses.mit;
              platforms = platforms.unix;
            };
          };
        }
      );
      apps = forAllSystems (
        pkgs: system:
        let
          inherit (pkgs) writeShellApplication;
          inherit (pkgs.lib.licenses) mit;
          inherit (pkgs.lib) concatStringsSep;
        in
        {
          docs = {
            type = "app";
            program = "${
              writeShellApplication {
                name = "gen-docs";
                runtimeInputs = with pkgs; [
                  coreutils
                  findutils
                  git
                  gnugrep
                  gnused
                  koka
                ];
                text = ''
                  # Selalu tulis ke <root repo>/docs, dari subfolder mana pun
                  # perintah ini dijalankan.
                  cd "$(git rev-parse --show-toplevel)"
                  mkdir -p docs

                  KOKA=${pkgs.koka}/bin/koka \
                  KOKA_FLAGS="${kokaLibArgs pkgs}" \
                    bash scripts/build-docs.sh docs ${concatStringsSep " " docModules}
                '';
              }
            }/bin/gen-docs";
            meta = {
              description = "Generate the API reference for util-kk";
              license = mit;
            };
          };
        }
      );

      # How a consuming flake reaches this library. `koki add` writes
      # `self.inputs.<input>.kokaLibraries.<system>.util.includePath`
      # when this flake is added as a dependency.
      kokaLibraries = forAllSystems (
        pkgs: system: {
          util =
            let
              package = self.packages.${system}.default;
            in
            {
              path = package;
              includePath = "${package}/share/koka/${pkgs.koka.version}";
              version = pkgs.koka.version;
              libVersion = package.version;
            };
        }
      );

      devShells = forAllSystems (
        pkgs: system:
        let
          inherit (pkgs) mkShell;
        in
        {
          default = mkShell {
            packages = with pkgs; [ koka ];
            shellHook = "printf '%s\\n' '${kokaJson pkgs}' > \"$PWD/koka.json\"";
          };
        }
      );

      checks = forAllSystems (
        pkgs: system:
        let
          inherit (pkgs) runCommand;
        in
        {
          build = self.packages.${system}.default;
          docs = self.packages.${system}.docs;

          # Compile and run a program against the installed package, through
          # the same include path that downstream flakes receive.
          consumer =
            runCommand "util-consumer"
              {
                nativeBuildInputs = [ pkgs.koka ];
                util = self.packages.${system}.default;
              }
              ''
                set -e
                export HOME="$TMPDIR"

                cat > main.kk <<'EOF'
                import util
                import utils/state
                import utils/reader
                import utils/exit
                import utils/het-cmp

                fun main()
                  println("%1-%2"%^["a", "b"])
                  val (r, s) = state/run(0) {
                    modify(_ + 1)
                    get()
                  }
                  println((r, s))
                  println(het/(==)(Just(1), Just(1)))
                EOF

                koka --include=$util/share/koka/${pkgs.koka.version} -e main.kk
                touch $out
              '';
        }
      );
    };
}
