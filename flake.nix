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
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system} system);

      # One Koka include directory per dependency. `koki add` writes the
      # lines between the markers below and `koki remove` takes them out;
      # the compiler flags and the editor include list further down are both
      # derived from them, so they cannot drift out of step with each other.
      kokaLibsFor = pkgs: [
        # koki:libs:start
        # koki:libs:end
      ];

      # `--include` flags for the compiler.
      kokaLibArgs = pkgs:
        builtins.concatStringsSep " " (map (d: "--include=${d}") (kokaLibsFor pkgs));

      # The same list as a `koka.json` `include_dirs` array, which is what
      # editors and the Koka language server read.
      kokaJson = pkgs:
        ''{"include_dirs":[${builtins.concatStringsSep "," (map (d: "\"${d}\"") (kokaLibsFor pkgs))}]}'';
    in
    {

      packages = forAllSystems (pkgs: system: {
        default = pkgs.stdenv.mkDerivation {
          pname = "util";
          version = "0.1.0";
          src = pkgs.lib.cleanSourceWith {
            src = self;
            filter = path: type:
              let base = baseNameOf (toString path);
              in !(builtins.elem base [ "result" "koka.json" ".koka" ]);
          };
          nativeBuildInputs = [ pkgs.koka pkgs.stdenv.cc ];

          buildPhase = ''
            runHook preBuild
            koka -l --output=util --builddir="$PWD/.koka-build" src/util.kk
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
      });

      # How a consuming flake reaches this library. `koki add` writes
      # `self.inputs.<input>.kokaLibraries.<system>.util.includePath`
      # when this flake is added as a dependency.
      kokaLibraries = forAllSystems (pkgs: system: {
        util = {
          path = self.packages.${system}.default;
          includePath = "${self.packages.${system}.default}/share/koka/${pkgs.koka.version}";
          version = pkgs.koka.version;
          libVersion = self.packages.${system}.default.version;
        };
      });

      devShells = forAllSystems (pkgs: system: {
        default = pkgs.mkShell {
          packages = [ pkgs.koka ];
          shellHook = "printf '%s\\n' '${kokaJson pkgs}' > \"$PWD/koka.json\"";
        };
      });

      checks = forAllSystems (pkgs: system: {
        build = self.packages.${system}.default;
      });
    };
}
