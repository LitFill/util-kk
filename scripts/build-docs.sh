#!/usr/bin/env bash
#
# Generate the HTML API reference for the util library.
#
# The Koka compiler's `--html` backend writes one page per module into a
# build directory: `<module>.xmp.html` (signatures, doc comments, inline
# table of contents) and `<module>-source.html` (annotated source). It emits no
# site scaffolding, though — every page links to `toc.html` and
# `styles/koka.css`, and neither is written. This script runs the compiler,
# collects its output, and supplies the missing pieces.
#
# Usage: scripts/build-docs.sh <out-dir>
#
# Environment:
#   KOKA                  koka binary            (default: koka on PATH)
#   KOKA_DOC_BASE         base URL for standard library links
#                         (default: https://koka-lang.github.io/koka/doc/)

set -euo pipefail

readonly KOKA="${KOKA:-koka}"
readonly KOKA_DOC_BASE="${KOKA_DOC_BASE:-https://koka-lang.github.io/koka/doc/}"

readonly MODULE_SLUG="util"
readonly SOURCE_FILE="src/util.kk"

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <out-dir>" >&2
  exit 64
fi

readonly OUT_DIR="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly SRC_FILE="$ROOT_DIR/$SOURCE_FILE"
readonly BUILD_DIR="$ROOT_DIR/.koka/docs"

die() { echo "error: $*" >&2; exit 1; }

# Locate the compiler output directory. Koka nests it as
# <builddir>/<koka-version>/<target-flags>/, and that depth is an internal
# detail that has changed between releases, so discover it rather than guess.
find_generated_dir() {
  local found
  # koka with -l (library mode) names output files as <src_file_without_kk>.xmp.html
  # e.g. src/util.kk -> src_util.xmp.html
  found="$(find "$BUILD_DIR" -type f -name "src_util.xmp.html" -printf '%h\n' 2>/dev/null | head -1)"
  [ -n "$found" ] || die "no src_util.xmp.html under $BUILD_DIR — did koka --html run?"
  printf '%s' "$found"
}



# The two pages for a module — the API view and the annotated source — are
# generated separately and do not agree on every anchor. A struct's generated
# field projections (`util/head`) exist only in the API view, because a
# field has no line of its own in the source view; `-l` likewise drops the page
# that carried the module anchor. Where a cross-page link points at an anchor
# that is not on the page it names, retarget it to the page that has it.
retarget_anchors() {
  local dir="$1" page self_page other_page anchor retargeted=0
  for page in "$dir/src_util.html" "$dir/src_util-source.html"; do
    if [ "$page" = "$dir/src_util.html" ]; then
      self_page="src_util.html"
      other_page="src_util-source.html"
    else
      self_page="src_util-source.html"
      other_page="src_util.html"
    fi
    while IFS= read -r anchor; do
      [ -n "$anchor" ] || continue
      # Only worth retargeting if the anchor is here and missing over there.
      grep -q "id=\"$anchor\"" "$page" || continue
      grep -q "id=\"$anchor\"" "$dir/$other_page" && continue
      grep -q "href=\"$other_page#$anchor\"" "$page" || continue
      sed -i "s|href=\"$other_page#$anchor\"|href=\"$self_page#$anchor\"|g" "$page"
      retargeted=1
    done < <(ids_of "$page")
  done
  [ "$retargeted" -eq 1 ] && echo "retargeted cross-page anchors that the compiler split across pages"
  return 0
}

ids_of() { grep -o 'id="[^"]*"' "$1" | sed 's/^id="//; s/"$//' | sort -u; }

# Koka links a module's name to `#_null_`, the anchor it places on a module
# page's heading. That heading carries no id, so give it the one the links
# expect.
add_module_anchor() {
  local api_page="$1/src_util.html"
  sed -i '0,/<h1>/s|<h1>|<h1 id="_null_">|' "$api_page"
  grep -q 'id="_null_"' "$api_page" || die "could not place the module anchor on src_util.html"
}

# Koka wraps each doc comment in `<xmp>`, a long-deprecated HTML element whose
# content is raw text: the browser never parses it. The compiler nevertheless
# puts real markup inside — the doc comment for a generated struct projection
# carries a `<code class="koka">` and a linked type — so that markup escapes
# as literal `<code class="koka">head</code>` on the page. Hand-written
# comments are plain prose with no markup inside, which is why only the
# compiler's own comments show it.
#
# The enclosing `<div class="doc koka comment">` is an ordinary element, so
# dropping the `<xmp>` wrapper is enough to let the markup render.
unwrap_raw_text_docs() {
  local api_page="$1/src_util.html"
  grep -q '<xmp>' "$api_page" \
    || die "no <xmp> in src_util.html — the compiler changed its doc markup; revisit this step"
  sed -i 's|<xmp>||g; s|</xmp>||g' "$api_page"
  # `if`, not `grep && die`: the success case is grep exiting non-zero, which
  # would return that status from the function and trip `set -e`.
  if grep -q '<xmp>' "$api_page"; then
    die "could not unwrap the doc comments in src_util.html"
  fi
}

# Every internal href the compiler emits must resolve, or the reference is
# full of dead links. Cross-check the anchors too, not just the file names.
verify_links() {
  local dir="$1" page href target anchor
  local missing=0
  for page in "$dir"/*.html; do
    [ -e "$page" ] || continue
    while IFS= read -r href; do
      target="${href%%#*}"
      anchor=""
      [ "$href" != "$target" ] && anchor="#${href#*#}"
      # Skip absolute URLs; only same-directory pages are ours to own.
      [ -n "$target" ] || continue
      case "$target" in http*|//*) continue ;; esac
      if [ ! -f "$dir/$target" ]; then
        echo "broken link in $(basename "$page"): $href" >&2
        missing=1
        continue
      fi
      if [ -n "$anchor" ] && ! grep -q "id=\"${anchor#\#}\"" "$dir/$target"; then
        echo "broken anchor in $(basename "$page"): $href" >&2
        missing=1
      fi
    done < <(grep -o 'href="[^"]*"' "$page" | sed 's/^href="//; s/"$//' | sort -u)
  done
  [ "$missing" -eq 0 ] || die "link verification failed"
}

main() {
  command -v "$KOKA" >/dev/null || die "koka not found on PATH (set KOKA)"

  local koka_version
  koka_version="$("$KOKA" --version | awk '/Koka/ { print $2; exit }')"
  [ -n "$koka_version" ] || die "could not read the koka version from '$KOKA --version'"

  rm -rf "$BUILD_DIR" "$OUT_DIR"
  mkdir -p "$OUT_DIR/styles"

  # `-l` builds a library, so the dummy `main` in the source does not become an
  # executable; `--target=c` keeps the C backend. `--htmlbases` sends every
  # `std/...` cross-reference to the published Koka documentation instead of
  # copying ~6 MB of standard library pages into this repository: those pages
  # describe Koka, not this library, and would drift from the compiler.
  "$KOKA" -l --html \
    --htmlbases="std=$KOKA_DOC_BASE" \
    --builddir="$BUILD_DIR" \
    "$SRC_FILE" >/dev/null

  local gen_dir api_page source_page
  gen_dir="$(find_generated_dir)"

  api_page="$gen_dir/src_util.xmp.html"
  source_page="$gen_dir/src_util-source.html"
  [ -f "$api_page" ] || die "koka produced no src_util.xmp.html"
  [ -f "$source_page" ] || die "koka produced no src_util-source.html"

  # Only this library's pages are shipped. `--htmlbases` above already points
  # every standard library cross-reference at the published Koka documentation,
  # and the compiler writes those pages to the build directory regardless;
  # copying them would add ~6 MB of an API that is not ours and can only go
  # stale against the compiler.
  #
  # The compiler links to `<module>.html` but writes `<module>.xmp.html`, so
  # rename on the way out to make the links it generated resolve.
  cp "$api_page" "$OUT_DIR/src_util.html"
  cp "$source_page" "$OUT_DIR/src_util-source.html"

  retarget_anchors "$OUT_DIR"
  add_module_anchor "$OUT_DIR"
  unwrap_raw_text_docs "$OUT_DIR"

  write_css "$OUT_DIR/styles/koka.css"
  write_toc "$OUT_DIR/toc.html" "$koka_version"
  write_index "$OUT_DIR/index.html" "$koka_version"

  # The scaffolding links into the generated pages; make sure the whole set is
  # closed before declaring success.
  verify_links "$OUT_DIR"

  echo "wrote $(find "$OUT_DIR" -type f | wc -l) files to $OUT_DIR"
}

write_css() {
  cat > "$1" <<'CSS'
/* Generated by scripts/build-docs.sh — do not edit.
   Styles the markup emitted by `koka --html`, which is Madoko-flavoured and
   carries no stylesheet of its own. */

:root {
  --bg: #ffffff;
  --bg-raised: #f6f8fa;
  --bg-sunken: #eef1f4;
  --fg: #1f2328;
  --fg-muted: #59636e;
  --fg-faint: #8c959f;
  --border: #d1d9e0;
  --link: #0b62c4;
  --link-hover: #084a94;
  --focus: #0969da;
  --kw: #b3247a;
  --type: #0b62c4;
  --var: #953800;
  --num: #0550ae;
  --comment: #59636e;
  --op: #7a3e9d;
  --code-bg: #f6f8fa;
  --shadow: 0 1px 2px rgba(31, 35, 40, .06), 0 4px 12px rgba(31, 35, 40, .05);
  --mono: "Roboto Mono", ui-monospace, "SFMono-Regular", "SF Mono", Menlo,
          Consolas, "Liberation Mono", monospace;
  --sans: "Nunito", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
          "Helvetica Neue", Arial, sans-serif;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0d1117;
    --bg-raised: #151b23;
    --bg-sunken: #010409;
    --fg: #e6edf3;
    --fg-muted: #9198a1;
    --fg-faint: #6e7681;
    --border: #3d444d;
    --link: #6cb6ff;
    --link-hover: #a5d2ff;
    --focus: #4493f8;
    --kw: #ff7b9c;
    --type: #6cb6ff;
    --var: #ffa657;
    --num: #79c0ff;
    --comment: #9198a1;
    --op: #d2a8ff;
    --code-bg: #151b23;
    --shadow: 0 1px 2px rgba(1, 4, 9, .4), 0 4px 12px rgba(1, 4, 9, .3);
  }
}

* { box-sizing: border-box; }

body.koka {
  margin: 0 auto;
  padding: 2rem 1.25rem 6rem;
  max-width: 62rem;
  background: var(--bg);
  color: var(--fg);
  font-family: var(--sans);
  font-size: 16px;
  line-height: 1.6;
  overflow-wrap: break-word;
}

a { color: var(--link); text-decoration: none; }

a:hover { color: var(--link-hover); text-decoration: underline; }

/* The scaffolding pages use <code> for inline identifiers; the compiler's own
   pages use <span> classes, so this cannot collide with them. */
code {
  padding: .12em .35em;
  border-radius: 4px;
  background: var(--code-bg);
  font-family: var(--mono);
  font-size: .875em;
}

pre > code { padding: 0; background: none; font-size: inherit; }

h2 {
  margin: 2.25rem 0 .75rem;
  font-size: 1.15rem;
  font-weight: 700;
  letter-spacing: -.01em;
}

h2::before {
  content: "# ";
  color: var(--fg-faint);
  font-family: var(--mono);
  font-weight: 400;
}

:focus-visible {
  outline: 2px solid var(--focus);
  outline-offset: 2px;
  border-radius: 3px;
}

/* ---- module page header ------------------------------------------------ */

body.koka > h1 {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  justify-content: space-between;
  gap: .5rem 1rem;
  margin: 0 0 1.5rem;
  padding-bottom: .75rem;
  border-bottom: 1px solid var(--border);
  font-family: var(--mono);
  font-size: 1.35rem;
  font-weight: 700;
}

.toc-link {
  font-family: var(--sans);
  font-size: .8rem;
  font-weight: 400;
  text-transform: uppercase;
  letter-spacing: .06em;
  color: var(--fg-muted);
}

/* ---- inline table of contents ------------------------------------------ */

div.toc {
  margin: 0 0 2rem;
  padding: 1rem 1.25rem;
  background: var(--bg-raised);
  border: 1px solid var(--border);
  border-radius: 8px;
}

div.toc > ul.toc {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
  gap: .1rem 1.5rem;
  margin: 0;
  padding: 0;
  list-style: none;
}

div.toc li.nested { padding-left: 1rem; }

/* The marker hangs off the link, not the list item: the link is a block, so a
   pseudo-element on the item would take a row of its own in the grid. */
div.toc li.nested a::before {
  content: "\00b7";
  margin-right: .4rem;
  color: var(--fg-faint);
}

div.toc a {
  display: block;
  padding: .12rem 0;
  font-family: var(--mono);
  font-size: .8rem;
  line-height: 1.5;
  color: var(--fg-muted);
  border-radius: 4px;
}

div.toc a:hover { color: var(--link-hover); text-decoration: none; }

/* ---- declarations ------------------------------------------------------ */

.decl {
  padding: .9rem 0 1rem;
  border-bottom: 1px solid var(--border);
  scroll-margin-top: 1rem;
}

.decl:target { background: var(--bg-raised); box-shadow: 0 0 0 .5rem var(--bg-raised); }

.decl > .header {
  font-family: var(--mono);
  font-size: .875rem;
  line-height: 1.65;
  overflow-x: auto;
}

.decl > .header .def { color: var(--fg); font-weight: 500; }

/* The doc comment's own element. `<xmp>` no longer appears: unwrap_raw_text_docs
   strips it so the compiler's inline markup can render. */
div.doc,
pre.doc {
  display: block;
  margin: .4rem 0 0;
  padding: .1rem 0 .1rem .85rem;
  border-left: 2px solid var(--border);
  font-family: var(--sans);
  font-size: .875rem;
  font-style: normal;
  line-height: 1.6;
  white-space: pre-wrap;
  color: var(--fg-muted);
}

div.nested { margin-left: 1.25rem; }
div.nested1 { margin-left: 1rem; }
div.nested2 { margin-left: .5rem; }

/* ---- syntax highlighting ----------------------------------------------- */

.kw, .decl-fun, .decl-type, .decl-con, .decl-val { color: var(--kw); font-weight: 600; }
.tp, .type, .mo { color: var(--type); }
.tpp, .tv { color: var(--var); font-style: italic; }
.number, .num { color: var(--num); }
.co, .comment { color: var(--comment); font-style: italic; }
.op, .effect, .st { color: var(--op); }
.lq, .param, .tpp, .def > span:not([class]) { color: var(--fg); }
.fslash, .dash { color: var(--fg-faint); }

/* `pp` wraps a type link with its fully qualified path. The compiler's inline
   style hides that path; keep it out of the way but still readable. */
.pp { color: inherit; text-decoration: none; }
.plaincode, a.pp .pc { display: none; }
a.pp:hover > .tp { text-decoration: underline; }
a.pp > .tp { border-bottom: 1px dotted var(--border); }

.last { color: var(--fg-faint); }
.sp { color: var(--fg-muted); }

/* ---- annotated source pages --------------------------------------------- */

body.koka pre.koka.source,
pre.source,
pre.nicecode {
  margin: 0;
  padding: 1.25rem 1.5rem;
  overflow-x: auto;
  background: var(--bg-raised);
  border: 1px solid var(--border);
  border-radius: 8px;
  font-family: var(--mono);
  font-size: .8125rem;
  line-height: 1.7;
  tab-size: 2;
}

pre a.pp { border-bottom: 1px dotted var(--border); }
pre a.pp:hover { background: var(--bg-sunken); }
pre .pc { display: none; }
pre .synopsis { color: var(--fg-muted); }
pre .index { color: var(--kw); font-weight: 600; }

/* ---- line anchors ------------------------------------------------------ */

.decl > .header a.link::after,
pre.source .line-anchor {
  content: "#";
  margin-left: .4rem;
  color: var(--fg-faint);
  opacity: 0;
  font-weight: 400;
  transition: opacity .12s ease-in-out;
}

.decl:hover > .header a.link::after { opacity: 1; }
.decl > .header a.link:hover::after { opacity: 1; color: var(--link); }

/* ---- narrow screens ---------------------------------------------------- */

@media (max-width: 40rem) {
  body.koka { padding: 1.25rem .9rem 4rem; font-size: 15px; }
  body.koka > h1 { font-size: 1.1rem; }
  div.toc > ul.toc { grid-template-columns: 1fr; }
  div.nested { margin-left: .5rem; }
  .decl > .header { font-size: .8125rem; }
  div.doc, pre.doc { padding-left: .6rem; }
}

@media (prefers-reduced-motion: reduce) {
  * { transition: none !important; }
}
CSS
}

write_toc() {
  local file="$1" koka_version="$2"
  cat > "$file" <<HTML
<!-- Generated by scripts/build-docs.sh — do not edit. -->
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>util — contents</title>
<link rel="stylesheet" href="styles/koka.css" />
</head>
<body class="koka doc">
<section aria-labelledby="this-project">
<h2 id="this-project">This project</h2>
<ul>
<li><a href="index.html">index</a> — this page</li>
<li><a href="src_util.html">util</a> — the <code>util</code> module and its operations</li>
<li><a href="src_util-source.html">util.kk source</a> — annotated source</li>
</ul>
<section aria-labelledby="stdlib">
<h2 id="stdlib">Koka standard library</h2>
<p>Types the API links to (<code>list</code>, <code>maybe</code>, <code>int</code>, …) are documented upstream.</p>
<ul>
  <li><a href="$KOKA_DOC_BASE" aria-label="Koka standard library documentation at koka-lang.github.io">Koka standard library ($koka_version)</a></li>
</ul>
</section>
</main>
</body>
</html>
HTML
}

write_index() {
  local file="$1" koka_version="$2"
  # Only the Koka version is shown: it is read from the compiler itself, and it
  # is what determines what the reference actually describes. The library's
  # own version would be a second source that can drift, for little gain.

  cat > "$file" <<HTML
<!-- Generated by scripts/build-docs.sh — do not edit. -->
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>util — Utility library Koka</title>
<meta name="description" content="API reference for util&lt;a&gt;, a library of utility functions for Koka." />
<meta name="theme-color" content="#0b62c4" />
<link rel="stylesheet" href="styles/koka.css" />
</head>
<body class="koka doc">
<main role="main">
<h1>Util-kk</h1>
<p>A small collection of general-purpose helpers for Koka — infix operators for
string templating and combinators for working with <code>std/text/parse</code>.</p>

go to toc: <a href="toc.html">toc</a>

<h2 id="usage">Usage</h2>

<pre class="koka source"><span class="kw">module</span> demo

<span class="kw">import</span> util

<span class="kw">fun</span> <span class="lq">main</span>() : <span class="tp">console</span> <span class="tp sp">()</span>
  println("%name!"!^("%name", "World"))</pre>

<p>Prints <code>Hello, World!</code>.</p>

<h2 id="install">Installation</h2>

<p>The flake exposes the library as <code>packages.default</code>, with resolved
paths under <code>kokaLibraries</code> for downstream flakes:</p>

<pre class="koka source">nix build <span class="lq">.packages.x86_64-linux.default</span>

<span class="lq">includePath</span>=<span class="lq">nix</span> <span class="lq">eval</span> --raw <span class="lq">.kokaLibraries.x86_64-linux.util.includePath</span></pre>
<p><code>nix develop</code> opens a shell that builds the library, puts it on the
module search path, and writes <code>koka.json</code>, so the example above runs
as-is.</p>

<h2 id="regenerate">Regenerating these docs</h2>

<p>These pages are produced by the Koka compiler's <code>--html</code> backend
plus the site scaffolding around it. To rebuild:</p>

<pre class="koka source">nix build <span class="lq">.docs</span>
<span class="comment"># or, from a checkout:</span>
scripts/build-docs.sh docs</pre>

</main>
</body>
</html>
HTML
}

main "$@"
