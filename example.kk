// # Example: using `util`
//
// Demonstrates the string-templating operators and the parser helpers
// from `util`, by parsing a minimal `let <name> = <integer>` binding.
//
// Run with:
//   nix develop
//   koka -e example.kk
module example

import std/text/parse

import src/util

// Parses a binding such as `let answer = 42`.
//
// `token` and `lex` consume trailing whitespace, so the grammar never needs to
// mention whitespace explicitly.
fun binding() : parse (string, int)
  token("let")
  val name = lex({ many1(alpha).string })
  token("=")
  val value = lex(pint)
  (name, value)

// Parses `input` and prints the outcome using the `show` function from `util`.
fun report(input: string) : console ()
  val result = parse(input.slice, binding)
  println("%1 => %2"%^[input.show, result.show])

fun main()
  // Single placeholder: the leading `%` is optional and added automatically.
  val greeting = "%greeting, %name!"!^("greeting", "Hello")!^("name", "World")
  println(greeting)  // Hello, World!

  // Multiple named placeholders in one call.
  val summary = "%user logged in from %host"!^^[("user", "LitFill"), ("host", "localhost")]
  println(summary)  // LitFill logged in from localhost

  // Positional placeholders.
  println("%1 + %2 = %3"%^["1", "2", "3"])  // 1 + 2 = 3

  // Parsing: one valid input and one invalid input.
  report("let answer = 42")  // ParseOk((answer, 42), rest=...)
  report("val answer = 42")  // ParseError(..., rest=...)
