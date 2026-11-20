# util-kk

`util-kk` is a library of utility functions for the Koka language. The library
is small. It has no third-party Koka dependencies. Use it in personal projects
and in downstream Nix flakes.

## Modules

The library has five modules.

| Module | Import | Contents |
| --- | --- | --- |
| `util` | `import util` | String templating functions. Parser helpers for `std/text/parse`. Maybe, list, and control flow helpers. |
| `state` | `import utils/state` | The `state` effect and the functions that use it. |
| `reader` | `import utils/reader` | The `reader` effect and the functions that use it. |
| `exit` | `import utils/exit` | The `exit` effect and the `exiting` function. |
| `het-cmp` | `import utils/het-cmp` | Comparison functions for values of different types. |

The modules are independent. Import only the modules that you need.

## Installation

### With `koki`

Run this command in another Koka project:

```bash
koki add LitFill:util-kk
```

### In a Nix flake

Add the input to your flake:

```nix
inputs.util-kk.url = "github:LitFill/util-kk";
```

Then add the include path to your Koka build:

```nix
kokaLibsFor = pkgs: [
  self.inputs.util-kk.kokaLibraries.${pkgs.stdenv.hostPlatform.system}.util.includePath
];
```

## Usage

Import the module that you need. The import path is the module path in the
include directory:

```koka
import util
```

The `state`, `reader`, `exit`, and `het-cmp` modules are in the `utils`
directory. Import them with the `utils/` prefix:

```koka
import utils/state
```

### String templating

Koka has no string interpolation syntax. The functions in `util` replace
placeholder text in a normal string.

| Function | Placeholder | Example |
| --- | --- | --- |
| `(!^)` | One named placeholder | `"Hello, %name!"!^("name", "World")` |
| `(!^^)` | A list of named placeholders | `"%a and %b"!^^[("a", "1"), ("b", "2")]` |
| `(%^)` | Positional placeholders `%1`, `%2`, ... | `"%1 + %2"%^["1", "2"]` |

Named placeholders:

- The leading `%` is optional. The functions add `%` when the placeholder has
  no `%` prefix. `"name"` and `"%name"` give the same result.
- `(!^)` replaces one placeholder. Chain `(!^)` to replace several
  placeholders.

Positional placeholders:

- `%1` takes the first value. `%n` takes the n-th value.
- The functions replace the placeholders in order, from `%1` upward.

Show functions:

- `default/(!^)`, `default/(!^^)`, and `default/(%^)` take values of any type
  that has a `show` function. These functions call `show` on each value.
- `(!^)`, `(!^^)`, and `(%^)` take strings only.

Cautions:

- The replacement is textual. `%1` is a prefix of `%10`. Use at most nine
  positional values.
- A replacement value that contains a placeholder can be replaced by a later
  pass.

Example:

```koka
fun example()
  val greeting = "%greeting, %name!"!^("greeting", "Hello")!^("name", "World")
  println(greeting)  // Hello, World!

  println("%1 + %2 = %3"%^[1, 2, 3])  // 1 + 2 = 3

  val total = "Total: %total"!^("total", 42)
  println(total)  // Total: 42
```

### Parser helpers

`util` has helpers for `std/text/parse`.

- `token(s)` parses the string `s` and consumes the whitespace after it. Use it
  for keywords and punctuation.
- `lex(p)` runs the parser `p` and consumes the whitespace after it. `lex` does
  not handle leading whitespace. Skip the first whitespace once, at the start of
  the grammar.
- `parser/run(input, parser)` parses `input` and returns `either<string, a>`.
  It returns `Right(value)` for a valid input. It returns `Left(message)` for an
  invalid input.
- `parse-error/show` renders a `parse-error<a>` value as a string. A success is
  `ParseOk(value, rest=...)`. A failure is `ParseError(message, rest=...)`.
  `rest` is the input that the parser did not consume.

Example:

```koka
import std/text/parse
import util

fun binding() : parse (string, int)
  token("let")
  val name = lex { many1(alpha).string }
  token("=")
  val value = lex(pint)
  (name, value)

fun main()
  val direct = "let answer = 42".slice.parse(binding)
  println(direct)  // ParseOk(("answer",42), rest="")

  val run = parser/run("let answer = 42", binding)
  println(run)  // Right(("answer",42))
```

### State

The `state` module gives the `state<a>` effect. `state/run(initial, action)`
runs `action` and returns the result and the final state.

```koka
fun example()
  val (result, st) = state/run(0) {
    modify(_ + 1)
    modify(_ * 10)
    get()
  }
  println((result, st))  // (10, 10)
```

| Function | Result |
| --- | --- |
| `state/run(initial, action)` | The result and the final state. |
| `handle-state(initial, action)` | The result. |
| `exec(initial, action)` | The final state. |
| `get()` | The current state. |
| `set(x)` | Unit. The state becomes `x`. |
| `modify(f)` | Unit. `f` sets the new state. |
| `gets(f)` | The value of `f(state)`. |
| `swap(new)` | The old state. The state becomes `new`. |
| `update(f)` | The new state. |
| `local(action)` | The result of `action`. The state is unchanged after `action`. |
| `modified(f, action)` | The result of `action`. `f` changes the state, and the change ends after `action`. |
| `zoom(getter, setter, action)` | The result of `action`. `action` uses a part of the state. |
| `fresh()` | The counter value. The counter increases by one. |
| `when(p, action)` | Unit. `action` runs when `p(state)` is `True`. |
| `while(p, action)` | Unit. `action` runs while `p(state)` is `True`. |

`zoom(getter, setter, action)` runs `action` in a state of type `b`. `getter`
maps the state of type `a` to the part of type `b`. `setter` writes the part
back into the state of type `a`.

### Reader

The `reader` module gives the `reader<a>` effect. `reader(env, action)` runs
`action` with the environment `env`.

```koka
fun example()
  val value = reader(10) {
    val outer = ask()
    val inner = local(_ + 5) { ask() }
    (outer, inner)
  }
  println(value)  // (10, 15)
```

| Function | Result |
| --- | --- |
| `reader(env, action)` | The result of `action` with `env`. |
| `reader-by(mk, action)` | The result of `action`. The action calls `mk` for each `ask`. |
| `handle-reader(env, action)` | The result of `action` with `env`. |
| `ask()` | The environment. |
| `asks(f)` | The value of `f(env)`. |
| `local(f, action)` | The result of `action`. `action` sees `f(env)`. |
| `focus(get, action)` | The result of `action`. `action` sees a part of the environment. |

`focus(get, action)` runs `action` with a part of the environment. `get`
selects the part, and `get` can use the outer reader. Inside `action`, `ask`
returns the part.

### Exit

The `exit` module gives the `exit` effect. `exiting(action)` runs `action` with
an `exit` handler.

```koka
fun example()
  exiting {
    println("before")
    exit()  // The next line does not run.
    println("after")
  }
  // Output: before
```

`exit()` stops `action` at once. The `exiting` call returns unit.

### Heterogeneous comparison

`het-cmp` compares two values. The values can have different types. Each
operator takes a comparison function for the operand types.

| Function | Result |
| --- | --- |
| `het/(==)(x, y)` | `True` when `x` is equal to `y`. |
| `het/(!=)(x, y)` | `True` when `x` is not equal to `y`. |
| `het/(>)(x, y)` | `True` when `x` is greater than `y`. |
| `het/(<)(x, y)` | `True` when `x` is less than `y`. |
| `het/(>=)(x, y)` | `True` when `x` is greater than or equal to `y`. |
| `het/(<=)(x, y)` | `True` when `x` is less than or equal to `y`. |

Call these functions with the full name and no space after the name:

```koka
fun example()
  println(het/(==)(Just(1), Just(1)))  // True
  println(het/(>)(2, 1))               // True
  println(not(het/(==)(1, 2)))         // True
```

`het/(==)`, `het/(>)`, `het/(<)`, `het/(>=)`, and `het/(<=)` take an implicit
`cmp` function. Koka resolves `cmp` from the operand types.

`het/(!=)` takes an implicit equality function. Koka 3.2.9 reports an ambiguity
for this function because it finds more than one equality function. Use
`not(het/(==)(x, y))` instead.

The names in `het-cmp` are close to the names of the standard comparison
operators. `import het-cmp` can make a plain `x > y` expression ambiguous. Koka
finds more than one function for `>`. Qualify the standard operator in this
case:

```koka
fun example()
  println(int/(>)(2, 1))  // True
```

### Other helpers in `util`

`util` has helpers for maybe, list, and control flow values.

| Function | Result |
| --- | --- |
| `maybe/flatmap(ma, f)` | The `maybe<b>` result of `f`. |
| `maybe/map2(ma, mb, f)` | `Just(f(a, b))`, or `Nothing` when one value is `Nothing`. |
| `maybe/zipwith(ma, mb, f)` | The same result as `maybe/map2`. |
| `maybe/zip(ma, mb)` | `Just((a, b))`, or `Nothing`. |
| `maybe2/zip(ma, mb)` | `Just2(a, b)`, or `Nothing2`. |
| `maybe/any(ma, pred)` | `False` for `Nothing`. Otherwise, the value of `pred` on the element. |
| `maybe/all(ma, pred)` | `True` for `Nothing`. Otherwise, the value of `pred` on the element. |
| `list/map2(xs, ys, f)` | The list of `f(x, y)` values. The result stops at the shorter list. |
| `list/map-maybe(xs, f)` | The list of values where `f` returns `Just`. |
| `list/map-maybe'(xs, f)` | The same result as `list/map-maybe`. |
| `and-then(a, b)` | A function that runs `a`, discards the result, and returns `b()`. |
| `forever(action)` | A function that never returns. It runs `action` without end. |

## Repository layout

| Path | Contents |
| --- | --- |
| `src/util.kk` | The `util` module. |
| `src/utils/state.kk` | The `state` module. |
| `src/utils/reader.kk` | The `reader` module. |
| `src/utils/exit.kk` | The `exit` module. |
| `src/utils/het-cmp.kk` | The `het-cmp` module. |
| `example.kk` | A program that shows the string and parser functions. |
| `bench.kk` | Benchmarks for the string templating functions. |
| `scripts/build-docs.sh` | The script that generates the API reference. |
| `assets/` | Stylesheet and page templates for the docs. |
| `flake.nix` | The Nix build and the flake outputs. |

## Development

Run these commands in the repository root:

```bash
nix develop          # Enter the development shell.
koka -e example.kk   # Run the example program.
nix build            # Build the library.
nix run .#docs       # Generate docs/ for every module.
```

The `docs/` directory contains the API reference for every module.

## License

The project uses the MIT License. See `LICENSE`.
