# util-kk

LitFill's utilities for Koka

## Using it

From another Koka project:

    koki add LitFill:util-kk

or by hand, in that project's `flake.nix`:

    inputs.util-kk.url = "github:LitFill/util-kk";

```nix
kokaLibsFor = pkgs: [
  self.inputs.util-kk.kokaLibraries.${pkgs.stdenv.hostPlatform.system}.util.includePath
];
```

## Layout

- `src/util.kk` — the library itself
- `example.kk` — a tiny program that imports it
- `flake.nix` — the build, and the `kokaLibraries` output other flakes use

## Commands

    koki build      # nix build
    koki check      # nix flake check
    koki dev        # nix develop
