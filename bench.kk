// # Benchmark: `util` string interpolators
//
// Stress tests `(!^)`, `(!^^)` and `(%^)` across several workloads:
// short templates, chained calls, many placeholders, long templates and large
// replacement values. A correctness check for the known `%1`/`%10` prefix
// limitation of `(%^)` runs at the end.
//
// Run with: koka -e -O1 bench.kk
module bench

import std/num/ddouble
import std/num/float64
import std/time/duration
import std/time/timer

import src/util

// Runs `action` for `iters` iterations and reports elapsed time and throughput.
//
// `action` receives the iteration index and returns an `int` (typically the
// length of the produced string). The results are summed and printed, so the
// computation cannot be discarded as dead code.
fun measure(label: string, iters: int, action: (int) -> int) : <ndet,console> ()
  val start = ticks()
  val sink  = list(1, iters).foldl(0, _ + _.action)
  val secs  = seconds(ticks() - start)
  val rate  = iters.float64 / secs.float64
  println("%1: %2 iters in %3s (%4 ops/s, checksum %5)"%^[
    label.pad-right(20),
    iters.show,
    secs.show,
    rate.show,
    sink.show
  ])

// Compares the result of a templating call against an expected string.
fun check(label: string, actual: string, expected: string) : console ()
  println("%1 %2: %3"%^[
    if actual == expected then "ok  " else "FAIL",
    label, actual.show
  ])

fun main()
  "== Performance ==".println

  // 1. Single placeholder, short template.
  measure("single (!^)      ", 200000) fn(i)
    count("Hello, %name!"!^("name", i.show))

  // 2. Five chained single replacements.
  measure("chained x5 (!^)  ", 100000) fn(i)
    count(
      "%a %b %c %d %e"
      !^("a", "1")
      !^("b", "2")
      !^("c", i.show)
      !^("d", "4")
      !^("e", "5"))

  // 3. Eight conversions in one call.
  val pairs = list(1, 8).map fn(k) ("k" ++ k.show, "value" ++ k.show)
  val tmpl8 = list(1, 8).map(fn(k) "%k" ++ k.show).join(" ")
  measure("list x8 (!^^)    ", 100000) fn(i)
    count(tmpl8 !^^ pairs)

  // 4. Nine positional arguments.
  val args9 = list(1, 9).map(show)
  val tmpl9 = list(1, 9).map(fn(k) "%" ++ k.show).join(",")
  measure("positional x9 (%^)", 100000) fn(i)
    count(tmpl9 %^ args9)

  // 5. Long template: 1000 occurrences of the same placeholder.
  val long = "%1 ".repeat(1000)
  measure("long template    ", 2000) fn(i)
    count(long %^ [i.show])

  // 6. Large replacement values: 10,000 characters each.
  val big = "x".repeat(10000)
  measure("large values     ", 2000) fn(i)
    count("[%1|%2]" %^ [big, big])

  // 7. No placeholder present: measures the cost of a pure scan.
  val plain = "no placeholders in this string at all ".repeat(50)
  measure("no match         ", 100000) fn(i)
    count(plain !^ ("missing", "x"))

  "".println
  "== Correctness ==".println

  check("single, optional prefix",
        "%name" !^ ("name", "Ada"), "Ada")
  check("repeated placeholder",
        "%1-%1-%1" %^ ["a"], "a-a-a")
  check("unused placeholder untouched",
        "%1 %2" %^ ["a"], "a %2")
  check("empty replacement",
        "[%1]" %^ [""], "[]")

  // Known limitation: `%1` is a prefix of `%10`, so with ten or more
  // arguments, `%10` is rewritten as the first argument followed by "0".
  // This check is expected to FAIL until the implementation is fixed.
  val ten = list(1, 10).map fn(k) "v" ++ k.show
  check("ten positional args (known issue)",
        "%10" %^ ten, "v10")

  // Known limitation: replacement values are scanned by later passes.
  check("replacement containing a placeholder (known issue)",
        "%1 %2" %^ ["%2", "b"], "%2 b")
