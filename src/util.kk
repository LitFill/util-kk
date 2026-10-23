// # Utilities
//
// A small collection of general-purpose helpers used across personal projects.
// The contents currently fall into two groups:
//
// - Infix operators for string templating, which substitute `%`-prefixed
//   placeholders with replacement values.
// - Helpers for working with `std/text/parse`, including a `show`
//   implementation for parse results and lexeme-style combinators.
module util

import std/text/parse

pub infixl 65 (!^), (!^^), (%^)

// Replaces every occurrence of a single placeholder in a string.
//
// The placeholder is given as the first element of `conversion`, and its
// replacement as the second. If the placeholder does not begin with `%`, the
// prefix is added automatically, so `"name"` and `"%name"` are equivalent.
//
// - `str`: the template string to operate on.
// - `conversion`: a `(placeholder, replacement)` pair.
//
// Returns a new string with all occurrences of the placeholder replaced.
//
// ```koka
// fun example()
//   val msg = "%greeting, %name!"!^("%greeting", "Hello")!^("%name", "World")
//   println(msg)  // Hello, World!
// ```
pub fun (!^)(str: string, conversion: (string, string)): string
    val (ptrn, repl)  = conversion
    val ptrn' = if ptrn.starts-with("%").is-just then ptrn else "%" ++ ptrn
    str.replace-all(ptrn', repl)

pub fun default/(!^)(str: string, conversion: (string, a), ?show: a -> e string) : e string
    val (ptrn, repl)  = conversion
    val ptrn' = if ptrn.starts-with("%").is-just then ptrn else "%" ++ ptrn
    str.replace-all(ptrn', repl.show)

// Replaces multiple named placeholders in a string.
//
// This is the list-based counterpart of `(!^)`. Each
// `(placeholder, replacement)` pair is applied in list order via a left fold,
// so later conversions operate on the output of earlier ones.
//
// - `str`: the template string to operate on.
// - `conversions`: a list of `(placeholder, replacement)` pairs.
//
// Returns a new string with all placeholders replaced.
//
// ```koka
// fun example()
//   val msg = "%greeting, %name!"!^^[("%greeting", "Hello"), ("%name", "World")]
//   println(msg)  // Hello, World!
// ```
pub fun (!^^)(str: string, conversions: list<(string, string)>): string
    conversions.foldl(str, _!^_)

pub fun default/(!^^)(str: string, conversions: list<(string, a)>, ?a/show: a -> e string): e string
    conversions.foldl(str, _!^_)

// Replaces positional placeholders (`%1`, `%2`, ...) with values from a list.
//
// Placeholders are numbered starting at 1, and the n-th element of `repls`
// replaces every occurrence of `%n`. Replacements are applied sequentially,
// from `%1` upward.
//
// - `str`: the template string to operate on.
// - `repls`: the replacement values, in positional order.
//
// Returns a new string with all positional placeholders replaced.
//
// Note: because replacement is textual and sequential, `%1` is a prefix of
// `%10`. Lists with ten or more elements may therefore produce incorrect
// output. Likewise, if a replacement value itself contains a placeholder
// (e.g. `"%2"`), it may be substituted by a later pass.
//
// ```koka
// fun example()
//   val msg = "%1, %2!"%^["Hello", "World"]
//   println(msg)  // Hello, World!
// ```
pub fun (%^)(str: string, repls: list<string>): string
    list(1, repls.length)
    .map("%" ++ _.show)
    .zip(repls)
    .foldl(str) fn(z, (ix, x))
        z.replace-all(ix, x)

pub fun default/(%^)(str: string, repls: list<a>, ?a/show: a -> e string): e string
    list(1, repls.length)
    .map("%" ++ _.show)
    .zip(repls)
    .foldl(str) fn(z, (ix, x))
        z.replace-all(ix, x.show)

// Renders a `parse-error<a>` as a human-readable string.
//
// Successful results are rendered as `ParseOk(value, rest=...)` and failures
// as `ParseError(message, rest=...)`, where `rest` is the unconsumed input.
// The `show` implementation for the payload type `a` is resolved implicitly.
//
// - `p`: the parse result to render.
//
// Returns the string representation of `p`.
//
// ```koka
// fun example()
//   val result = parse(input.slice, token("let"))
//   println(result.show)  // ParseOk("let", rest=...)
// ```
pub fun parse-error/show(p: parse-error<a>, ?a/show: a -> e string) : e string
    match p
        ParseOk(x, rest) ->
            "ParseOk(%1, rest=%2)"%^[x.show, rest.show]
        ParseError(msg, rest) ->
            "ParseError(%1, rest=%2)"%^[msg.show, rest.show]

// Turns a parser into a lexeme parser by discarding trailing whitespace.
//
// The parser `p` is run first, and any whitespace that follows it is then
// consumed (via `whitespace0`) and discarded. The result of `p` is returned
// unchanged. Leading whitespace is not handled, so a grammar built from
// lexemes should skip any initial whitespace once, at its entry point.
//
// - `p`: the parser to wrap.
//
// Returns the result of `p`, after trailing whitespace has been consumed.
//
// ```koka
// fun example()
//   "67   \n".slice.parse {
//     with lex
//     pint()
//   } .println
//   // ^ ParseOk(64, rest="")
// ```
pub fun lex(p: parser<e, a>): <parse|e> a
    val x = p()
    whitespace0()
    x

// Parses an exact string and consumes any whitespace that follows it.
//
// This is the lexeme version of `pstring`, and is intended for keywords,
// operators and punctuation. It fails if the input does not begin with `s`.
//
// - `s`: the literal string to match.
//
// Returns the matched string.
//
// ```koka
// fun example()
//   token("let")
//   val name = p-name()
//   token("=")
//   val expr = p-expr()
//   Let(name, expr)
//   // "let    x     =    <expr>\n...rest" -> ParseOk(Let("x", <expr>), rest="...rest")
// ```
pub fun token(s: string) : parse string
    with lex
    pstring(s)
