# util-kk

Utilities for Koka: a small library for string templating and parser helpers.

`util-kk` is a lightweight Koka library intended for personal projects and downstream flakes. It currently provides:

- string interpolation helpers for named and positional placeholders
- parser utilities built around `std/text/parse`
- a convenient `show` implementation for parse results
- a `lex` helper that consumes trailing whitespace for token-based grammars

## Why use it?

This library helps when you want cleaner formatting and simpler parsing code in Koka without pulling in a larger framework.

Common examples include:

- building user-facing strings with `%name` and `%1` placeholders
- writing small recursive-descent parsers without repeating whitespace handling
- rendering parse results in a readable, debug-friendly form

## Installation

### With `koki`

From another Koka project:

```bash
koki add LitFill:util-kk
```

### By hand in a flake

```nix
inputs.util-kk.url = "github:LitFill/util-kk";
```

Then expose the library to your Koka build:

```nix
kokaLibsFor = pkgs: [
  self.inputs.util-kk.kokaLibraries.${pkgs.stdenv.hostPlatform.system}.util.includePath
];
```

## Usage

The library is imported as:

```koka
import util
```

or, if you are using a project layout with a `src/` directory:

```koka
import src/util
```

### String templating

```koka
val greeting = "%greeting, %name!"!^("greeting", "Hello")!^("name", "World")
println(greeting)  // Hello, World!

val summary = "%user logged in from %host"!^^[("user", "LitFill"), ("host", "localhost")]
println(summary)  // LitFill logged in from localhost

println("%1 + %2 = %3"%^ [1, 2, 3])  // 1 + 2 = 3
```

### Parsing helpers

The library includes helpers for `std/text/parse`, including `lex` and `token`:

```koka
import std/text/parse
import util

fun binding() : parse (string, int)
  token("let")
  val name = lex({ many1(alpha).string })
  token("=")
  val value = lex(pint)
  (name, value)
```

This pattern is demonstrated in `example.kk`.

## Example

The repository includes a small example program:

- `example.kk` — demonstrates string interpolation and parser helpers

Run it with:

```bash
nix develop
koka -e example.kk
```

## Repository layout

- `src/util.kk` — the library itself
- `example.kk` — example usage
- `flake.nix` — Nix build and flake outputs for downstream consumers

## Development commands

```bash
koki build      # nix build
koki check      # nix flake check
koki dev        # nix develop
```

## License

This project is licensed under the MIT License.
