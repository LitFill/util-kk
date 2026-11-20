#!/usr/bin/env bash
#
# Generate the HTML API reference for util-kk.
#
# The Koka compiler's `--html` backend writes two pages per module into a
# build directory: `<slug>.xmp.html` (signatures, doc comments, inline table
# of contents) and `<slug>-source.html` (annotated source). It writes no site
# scaffolding, so this script runs the compiler, collects the pages, and
# supplies the stylesheet, the table of contents, and the landing page.
#
# Usage: scripts/build-docs.sh [--check] <out-dir> [module.kk]...
#
#   --check   build into a temporary directory and compare it with <out-dir>;
#             exit non-zero when they differ. Nothing is written to <out-dir>.
#
#   With no module argument, the script builds src/util.kk.
#
# Paths are relative to the repository root.
#
# Environment:
#   KOKA             koka binary (default: koka on PATH)
#   KOKA_DOC_BASE    base URL for standard library links
#                    (default: https://koka-lang.github.io/koka/doc/)
#   KOKA_BUILD_DIR   compiler output directory (default: <repo>/.koka/docs)
#   KOKA_ASSETS      directory with koka.css, toc.html, index.html
#                    (default: <repo>/assets)

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

CHECK=0
if [ "${1:-}" = "--check" ]; then
  CHECK=1
  shift
fi

if [ "$#" -lt 1 ]; then
  echo "usage: $0 [--check] <out-dir> [module.kk]..." >&2
  exit 64
fi

OUT_ARG="$1"
shift
if [ "$#" -eq 0 ]; then
  MODULES=("src/util.kk")
else
  MODULES=("$@")
fi

while [ "${OUT_ARG%/}" != "$OUT_ARG" ] && [ "$OUT_ARG" != "/" ]; do
  OUT_ARG="${OUT_ARG%/}"
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
cd "$ROOT_DIR"

readonly KOKA="${KOKA:-koka}"
KOKA_DOC_BASE="${KOKA_DOC_BASE:-https://koka-lang.github.io/koka/doc/}"
readonly KOKA_DOC_BASE="${KOKA_DOC_BASE%/}/"
readonly BUILD_DIR="${KOKA_BUILD_DIR:-$ROOT_DIR/.koka/docs}"
readonly ASSETS="${KOKA_ASSETS:-$ROOT_DIR/assets}"

case "$OUT_ARG" in
  "" | "/" | "." | "..") die "refusing to use '$OUT_ARG' as the output directory" ;;
  */. | */..) die "refusing to use '$OUT_ARG' as the output directory" ;;
esac
[ "$OUT_ARG" = "$ROOT_DIR" ] && die "refusing to use the repository root as the output directory"

case "$BUILD_DIR" in
  "" | "/" | "." | "..") die "refusing to use '$BUILD_DIR' as the build directory" ;;
esac

command -v "$KOKA" >/dev/null || die "koka not found on PATH (set KOKA)"

for asset in koka.css toc.html index.html; do
  [ -f "$ASSETS/$asset" ] || die "missing asset: $ASSETS/$asset"
done

for m in "${MODULES[@]}"; do
  [ -f "$m" ] || die "no such module: $m"
done

# Koka names the generated files after the source path with `/` turned into
# `_` and `-` into `_dash_`: src/utils/het-cmp.kk -> src_utils_het_dash_cmp.
slug_of() {
  local p="${1%.kk}"
  p="${p//\//_}"
  printf '%s' "${p//-/_dash_}"
}

# The links inside the generated pages use the module path with `/` turned
# into `_` and the `-` kept: src/utils/het-cmp.kk -> src_utils_het-cmp. The
# output files take the link name so those links resolve.
link_of() {
  local p="${1%.kk}"
  printf '%s' "${p//\//_}"
}

name_of() {
  local p="${1##*/}"
  printf '%s' "${p%.kk}"
}

ids_of() { grep -o 'id="[^"]*"' "$1" | sed 's/^id="//; s/"$//' | sort -u; }

# The API view and the annotated source view do not agree on every anchor. A
# struct's generated field projections (`util/head`) exist only in the API
# view, because a field has no line of its own in the source view. Where a
# cross-page link points at an anchor that is not on the page it names,
# retarget it to the page that has it.
retarget_anchors() {
  local api="$1" source="$2"
  local api_name source_name page self_page other_page other_path anchor retargeted=0
  api_name="$(basename "$api")"
  source_name="$(basename "$source")"
  for page in "$api" "$source"; do
    if [ "$page" = "$api" ]; then
      self_page="$api_name"
      other_page="$source_name"
    else
      self_page="$source_name"
      other_page="$api_name"
    fi
    other_path="$(dirname "$page")/$other_page"
    while IFS= read -r anchor; do
      [ -n "$anchor" ] || continue
      # Only worth retargeting if the anchor is here and missing over there.
      grep -qF "id=\"$anchor\"" "$page" || continue
      grep -qF "id=\"$anchor\"" "$other_path" && continue
      grep -qF "href=\"$other_page#$anchor\"" "$page" || continue
      sed -i "s|href=\"$other_page#$anchor\"|href=\"$self_page#$anchor\"|g" "$page"
      retargeted=1
    done < <(ids_of "$page")
  done
  [ "$retargeted" -eq 1 ] && echo "retargeted cross-page anchors that the compiler split across pages"
  return 0
}

# Koka links a module's name to `#_null_`, the anchor it places on a module
# page's heading. That heading carries no id, so give it the one the links
# expect.
add_module_anchor() {
  local api_page="$1"
  sed -i '0,/<h1>/s|<h1>|<h1 id="_null_">|' "$api_page"
  grep -q 'id="_null_"' "$api_page" || die "could not place the module anchor on $api_page"
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
  local api_page="$1"
  grep -q '<xmp>' "$api_page" || return 0
  sed -i 's|<xmp>||g; s|</xmp>||g' "$api_page"
  if grep -q '<xmp>' "$api_page"; then
    die "could not unwrap the doc comments in $api_page"
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
      case "$target" in http* | //*) continue ;; esac
      if [ ! -f "$dir/$target" ]; then
        echo "broken link in $(basename "$page"): $href" >&2
        missing=1
        continue
      fi
      # Koka links private struct fields (`person_fs_age`) that it never gives
      # an id, so the annotated source pages cannot be anchor-checked. The API
      # pages can.
      case "$page" in *-source.html) continue ;; esac
      if [ -n "$anchor" ] && ! grep -qF "id=\"${anchor#\#}\"" "$dir/$target"; then
        echo "broken anchor in $(basename "$page"): $href" >&2
        missing=1
      fi
    done < <(grep -o 'href="[^"]*"' "$page" | sed 's/^href="//; s/"$//' | sort -u)
  done
  [ "$missing" -eq 0 ] || die "link verification failed"
}

# Locate the compiler output directory. Koka nests it as
# <builddir>/<koka-version>/<target-flags>/, and that depth is an internal
# detail that has changed between releases, so discover it rather than guess.
find_generated_dir() {
  local first found
  first="$(slug_of "${MODULES[0]}")"
  found="$(find "$BUILD_DIR" -type f -name "$first.xmp.html" 2>/dev/null)"
  found="${found%%$'\n'*}"
  [ -n "$found" ] || die "no $first.xmp.html under $BUILD_DIR — did koka --html run?"
  dirname "$found"
}

# One list item per module, linking the API page and the annotated source.
module_links() {
  local m link name
  for m in "${MODULES[@]}"; do
    link="$(link_of "$m")"
    name="$(name_of "$m")"
    printf '<li><a href="%s.html">%s</a> — <a href="%s-source.html">annotated source</a></li>\n' \
      "$link" "$name" "$link"
  done
}

# Render a template: a line that is exactly `<!-- modules -->` is replaced by
# the module list, and the version and base URL are substituted inline.
render_page() {
  local tpl="$1" out="$2" modules="$3" version="$4"
  local line
  while IFS= read -r line; do
    if [ "$line" = "<!-- modules -->" ]; then
      printf '%s\n' "$modules"
    else
      line="${line//<!-- version -->/$version}"
      line="${line//<!-- koka-base -->/$KOKA_DOC_BASE}"
      printf '%s\n' "$line"
    fi
  done < "$tpl" > "$out"
}

write_toc() {
  local file="$1" version="$2" modules="$3"
  render_page "$ASSETS/toc.html" "$file" "$modules" "$version"
}

write_index() {
  local file="$1" version="$2" modules="$3"
  render_page "$ASSETS/index.html" "$file" "$modules" "$version"
}

generate() {
  local out="$1"
  local koka_version line gen_dir m slug link api_page source_page modules_html

  rm -rf "$out"
  mkdir -p "$out/styles"
  cp "$ASSETS/koka.css" "$out/styles/koka.css"

  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"

  koka_version=""
  while IFS= read -r line; do
    if [ "${line#Koka }" != "$line" ]; then
      koka_version="${line#Koka }"
      koka_version="${koka_version%% *}"
      koka_version="${koka_version%,}"
      break
    fi
  done <<< "$("$KOKA" --version)"
  [ -n "$koka_version" ] || die "could not read the koka version from '$KOKA --version'"

  # `-l` builds a library, so a dummy `main` in the source does not become an
  # executable. `--htmlbases` sends every `std/...` cross-reference to the
  # published Koka documentation instead of copying ~6 MB of standard library
  # pages into this repository: those pages describe Koka, not this library,
  # and would drift from the compiler.
  "$KOKA" -l --html \
    --htmlbases="std=$KOKA_DOC_BASE" \
    --builddir="$BUILD_DIR" \
    "${MODULES[@]}" >/dev/null

  gen_dir="$(find_generated_dir)"

  for m in "${MODULES[@]}"; do
    slug="$(slug_of "$m")"
    link="$(link_of "$m")"
    api_page="$gen_dir/$slug.xmp.html"
    source_page="$gen_dir/$slug-source.html"
    [ -f "$api_page" ] || die "koka produced no $slug.xmp.html"
    [ -f "$source_page" ] || die "koka produced no $slug-source.html"

    # The compiler links to `<module>.html` but writes `<module>.xmp.html`, so
    # rename on the way out to make the links it generated resolve.
    cp "$api_page" "$out/$link.html"
    cp "$source_page" "$out/$link-source.html"

    # Koka writes some hrefs with the file slug (`het_dash_cmp`) and some with
    # the module path (`het-cmp`). Normalize every href to the link name so the
    # copied pages agree with their own file names.
    sed -i "s|href=\"$slug|href=\"$link|g" "$out/$link.html" "$out/$link-source.html"

    retarget_anchors "$out/$link.html" "$out/$link-source.html"
    add_module_anchor "$out/$link.html"
    unwrap_raw_text_docs "$out/$link.html"
  done

  modules_html="$(module_links)"
  write_toc "$out/toc.html" "$koka_version" "$modules_html"
  write_index "$out/index.html" "$koka_version" "$modules_html"

  # The scaffolding links into the generated pages; make sure the whole set
  # is closed before declaring success.
  verify_links "$out"

  echo "wrote $(find "$out" -type f | wc -l) files to $out"
}

main() {
  local tmp status old

  if [ "$CHECK" = 1 ]; then
    tmp="$(mktemp -d)"
    generate "$tmp"
    status=0
    diff -r "$tmp" "$OUT_ARG" || status=$?
    rm -rf "$tmp"
    [ "$status" -eq 0 ] || die "docs are stale: $OUT_ARG differs from a fresh build"
    echo "docs are up to date: $OUT_ARG"
    return 0
  fi

  # Build beside the target, then swap, so a failed build leaves the current
  # docs in place.
  tmp="${OUT_ARG}.tmp.$$"
  rm -rf "$tmp"
  generate "$tmp"

  if [ -e "$OUT_ARG" ]; then
    old="${OUT_ARG}.old.$$"
    rm -rf "$old"
    mv "$OUT_ARG" "$old"
    mv "$tmp" "$OUT_ARG"
    rm -rf "$old"
  else
    mv "$tmp" "$OUT_ARG"
  fi
}

main "$@"
