# TODO

Tracking for the documentation generator (`scripts/build-docs.sh`) and the
flake that runs it.

## P0 — wrong output today

- [x] **Version string has a trailing comma.** `awk '/Koka/ {print $2}'`
  returned `3.2.9,` because `koka --version` prints
  `Koka 3.2.9, 00:00:00 …`. The version is now parsed in bash and the comma
  is stripped; `docs/toc.html` shows `(3.2.9)`.
- [x] **`toc.html` has a stray `</main>`.** The template now opens and closes
  `<main>`, and both `<section>` elements are closed.
- [x] **Index claims the wrong output.** The hand-written index is gone. The
  page is now a generated landing page with no sample output.
- [x] **Index claims `nix develop` puts the library on the search path.** The
  claim was removed with the old index.
- [x] **`rm -rf "$OUT_DIR"` is unguarded.** The script refuses `.`, `..`, `/`,
  empty, and the repository root. It builds into `<out>.tmp.$$` and swaps only
  after a successful build.
- [x] **The app uses GNU-only tools on non-GNU hosts.** `find -printf` is gone.
  `apps.docs` now has `coreutils`, `findutils`, `gnugrep`, and `gnused` in
  `runtimeInputs`.

## P1 — structure

- [x] **Move assets out of the script.** `assets/koka.css`, `assets/toc.html`,
  and `assets/index.html`; the script keeps only logic.
- [x] **Parameterize the module list.** `slug_of`/`link_of` derive the page
  names from the path, the script loops over `<module.kk>...`, and the flake
  passes `docModules`.
- [x] **Add `--check` mode.** Generates into a temporary directory and
  `diff -r`s it against the target; exits non-zero on drift.
- [x] **Add `checks.docs-fresh`.** The derivation is in the flake;
  `nix flake check` runs four checks and all pass.
- [x] **Normalize `KOKA_DOC_BASE`.** `${KOKA_DOC_BASE%/}/` strips a trailing
  slash before adding one.

## P2 — polish

- [x] **Quote the heredocs.** The HTML is now read from template files and
  rendered line by line, so nothing expands.
- [x] **Drop the hand-written syntax highlighting.** The landing page has no
  code sample.
- [ ] **Fixture tests for the transforms.** `retarget_anchors`,
  `unwrap_raw_text_docs`, and `verify_links` are pure text transforms with no
  tests. Optional.

## Verification

- `scripts/build-docs.sh` builds 13 files for all five modules.
- Two runs are byte-identical.
- `--check` passes on a fresh build and fails on a tampered one.
- `nix run .#docs` regenerates `docs/` and exits 0.
- `nix flake check` runs `build`, `docs`, `docs-fresh`, and `consumer`; all
  pass.

Nix only copies tracked files into the flake source. The new `assets/` and
`docs/` files must be staged (`git add`) before `checks.docs-fresh` can see
them.