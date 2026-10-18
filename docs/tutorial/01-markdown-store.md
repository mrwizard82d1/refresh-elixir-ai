# Stage 1: No storage, so the markdown file is the database

**Goal:** `mix tt.report PATH` reads your markdown time log and prints this week's totals per
description, per day, and for the whole week. Every run re-parses the whole file. Nothing is
stored.

## The spec

These are your decisions:

| Rule | Decision |
|---|---|
| Day header | `# dd-MMM`, e.g. `# 16-Oct` |
| Record | `hhmm description`; `hhmm` is the **start** time, and the activity runs until the next record |
| End of day | `hhmm out` ends the last activity. A day without one is an **error** |
| Year | The current year, or the previous year if the date would otherwise be in the future |
| Bad input | **Reject the file**, reporting *every* error with its line number |
| "This week" | **Sunday** to Saturday, inclusive |
| Report | Total per description, total per day, grand total |

These smaller details are **proposals of mine**. The tests encode them, so say so *before* you
start if you'd like any of them changed:

| Detail | Proposal |
|---|---|
| Header strictness | Exactly `# ` + two-digit day + `-` + English month abbreviation in title case (`Oct`, not `oct`) |
| `out` | Exactly the word `out`. `1730 out early` is an activity called "out early" |
| Descriptions | Leading and trailing whitespace trimmed; grouped by exact, case-sensitive text |
| Blank lines | Ignored everywhere |
| Times | Must strictly increase within a day; equal times are an error. No crossing midnight |
| Error reasons | Atoms: `:invalid_time`, `:missing_description`, `:invalid_header`, `:invalid_date`, `:content_before_header`, `:missing_out`, `:time_not_increasing`, `:record_after_out`, `:duplicate_day` |
| Report layout | Descriptions alphabetical, days in date order, durations as `h:mm` (see the `format/1` test) |
| CLI | `mix tt.report PATH [--from YYYY-MM-DD] [--to YYYY-MM-DD]`; on errors it fails with `line N: reason` lines |

## How to work through this stage

The tests are already written, in [`01-tests/`](01-tests). Each exercise tells you which file to
copy into `time_tracker/test/`. Then:

1. **Run it and watch it fail.** Read the failure and predict what you'll need before writing
   anything.
2. Make it pass with the **smallest** change, one test or `describe` block at a time:
   `mix test --only describe:"parse_time/1"` runs a single block.
3. Refactor while it's green: `mix format`, `mix credo --strict`.
4. Commit, then tell me you're ready for a review.

**Where the code goes:** `lib/time_tracker/<name>.ex` for `TimeTracker.<Name>`. The Mix task goes
in `lib/mix/tasks/tt.report.ex`.

**Test style:** some tests use a `for` loop around `test` to generate **one test per input**, so
every failing input shows up separately rather than stopping at the first one. That's ExUnit's
answer to soft assertions.

---

## Exercise 1.0: The acceptance test (outer loop)

```sh
cd time_tracker
mkdir -p test/mix/tasks
cp ../docs/tutorial/01-tests/mix/tasks/tt.report_test.exs test/mix/tasks/
mix test test/mix/tasks/tt.report_test.exs
```

**Expect red:** a compile warning that `Mix.Tasks.Tt.Report.run/1` is undefined, then 3 failures
with `UndefinedFunctionError`. **This test stays red until exercise 1.8.** It's the outer loop:
it tells you when the whole feature works, while exercises 1.1–1.7 are the inner loops that get
you there.

Read the test before going on, noticing these:
- `@moduletag :tmp_dir`: ExUnit creates a fresh temporary directory for each test and passes it in
  the context.
- `capture_io/1` collects what the task prints.
- `:calendar.local_time()` comes from Erlang and returns `{{y, m, d}, {h, min, s}}` tuples.
  `Date.utc_today/0` would give the wrong date on a US evening, so "today" is local.
- No `async: true`. The Mix shell is global state.

## Exercise 1.1: Structs: `Activity` and `Day`

```sh
mkdir -p test/time_tracker
cp ../docs/tutorial/01-tests/time_tracker/activity_test.exs test/time_tracker/
```

**Expect red:** a **compile error**, not a test failure. A struct literal (`%Activity{...}`) is
expanded at compile time, so the module must exist before the test can even compile.

Write `TimeTracker.Activity` (fields `start`, `stop`, `description`, with `minutes/1`) and
`TimeTracker.Day` (fields `date`, `activities`). There's no test file for `Day`: the parser tests
in 1.5 cover it.

Concepts to refresh:
- `defstruct` and `@enforce_keys`. What does `%Activity{description: "x"}` do at compile time,
  compared with `struct!(Activity, description: "x")` at runtime?
- `@type t :: %__MODULE__{...}` and `@spec`, the `t()` convention from task 0.9
- `Time.diff/3` and its unit argument

Why `minutes/1` is a function and not a field: a stored `minutes` could disagree with `start` and
`stop`. A computed one can't. That's "illegal states unrepresentable", in a small way.

## Exercise 1.2: `Parser.parse_time/1`: binary pattern matching

```sh
cp ../docs/tutorial/01-tests/time_tracker/parser_test.exs test/time_tracker/
mix test --only describe:"parse_time/1"
```

The file has tests for 1.2–1.5. Use `--only` to work on one block at a time.

`"0915"` should become `{:ok, ~T[09:15:00]}`, and anything else `{:error, :invalid_time}`. Look
at the rejected inputs: `"+915"` and `" 915"` are the traps.

Concepts to refresh:
- matching *inside* a binary in a function head: `<<a, b, c, d>>` matches exactly four bytes, and
  `<<h::binary-size(2), rest::binary>>` splits off a prefix
- guards, and `defguard`/`defguardp` for naming one you reuse
- `?0` is the integer code point of the character `0`
- `Time.new/3` validates hours and minutes for you, so don't re-implement the range checks
- multiple function clauses as the "else" branch: a final `def parse_time(_)`

Ask yourself why `Integer.parse/1` is a trap here. Try `Integer.parse("+9")` in IEx.

## Exercise 1.3: `Parser.parse_record/1`: `with` and multi-clause dispatch

```sh
mix test --only describe:"parse_record/1"
```

Return `{:ok, {:start, time, description}}`, `{:ok, {:out, time}}` or `{:error, reason}`.

Concepts to refresh:
- `String.split/3` with `parts: 2`, and `String.trim/1`
- `with`: chain the steps that can fail. When a step fails to match, `with` returns that
  non-matching value. Do you need an `else` clause here?
- private multi-clause functions (`defp classify(...)`) as an alternative to nested `case`/`if`.
  The clause order *is* the logic

## Exercise 1.4: `Parser.parse_header/2`: inferring the year

```sh
mix test --only describe:"parse_header/2"
```

`parse_header("# 16-Oct", today)` returns `{:ok, date}`. Note the design: **`today` is a
parameter**. The clock is I/O, so the parser doesn't read it. The test can then pin "today" to
any date, such as 2-Jan-2027 for the year rollover.

Concepts to refresh:
- binary matching with a literal prefix: `<<"# ", rest::binary>>`
- module attributes computed **at compile time**: building a month lookup map once with
  `@months ... |> Map.new()`
- `Map.fetch/2` returns `{:ok, v}` or `:error`, which differs from `Map.get/3`
- **term ordering**: tuples compare element by element, so `{month, day} > {10, 17}` is a valid
  "later in the year" test. Erlang's total term order is useful here.
- the 29-Feb tests: which order (choose the year, then build the date, or the other way round)
  makes them pass?

---

> **Recap: binaries and charlists** (once 1.2–1.4 are green)
>
> Everything you matched in 1.2–1.4 was a **binary**. An Elixir string *is* an Erlang binary
> holding UTF-8. `<<h1, ...>>` matched its **bytes**, which is safe only because digits, `#`,
> `-` and English month names are all one byte each. A charlist (`~c"0915"`) is a *list* of
> integers, so `<<...>>` patterns would never match one. At an Erlang boundary, read the spec
> (`string()` is a charlist, `binary()` is a binary) and convert with `to_charlist/1` /
> `to_string/1`.

---

## Exercise 1.5: `Parser.parse/2`: the whole document

```sh
mix test --only describe:"parse/2"
```

This is the largest exercise. Take the tests **in file order**, since each adds one rule. Return
`{:ok, [%Day{}]}` or `{:error, [{line_number, reason}]}`, with errors sorted by line.

A pipeline shape that works:

1. split into lines, number them (`Enum.with_index(lines, 1)`), and drop blank ones
2. separate any lines before the first header (`Enum.split_while/2`)
3. group the rest into days: one header plus its records. Look at `h Enum.chunk_while`, which you
   met in task 0.9
4. parse each day into `{:ok, day}` or `{:error, errors}`
5. check for duplicate dates (a `MapSet` is a good fit) and gather every error

Concepts to refresh:
- errors as **data**: collecting a list of `{line, reason}` instead of stopping at the first
  problem. This is why the parser returns tuples rather than raising.
- recursion with pattern matching on the *front* of a list (`[a, b | rest]`) to pair each record
  with the next one
- `Time.compare/2`: why can't you use `<` on two `Time` structs? Try
  `~T[10:00:01.5] > ~T[10:01:00]` and `~D[2026-01-31] > ~D[2026-02-01]` in IEx. Both return
  `true`. Structs compare as maps, key by key in *alphabetical* key order, so `:day` is compared
  before `:month`, and `:microsecond` before `:minute`.
- Keep functions small. If one starts needing nested `case`/`with`, split it. Credo's
  cyclomatic-complexity check (`mix credo --strict`) flags anything above 9.

**Your call (not tested):** what about a day containing only `0900 out`? Decide whether it's an
error or an empty day, then write the test *first*.

---

> **Recap: the type checker** (if it warned you during 1.5)
>
> A warning such as "this clause will never match" or "comparison between distinct types" comes
> from the **compiler**, not the test run (task 0.6). `dynamic(...)` around a type means it was
> **inferred**, not declared. The warning fires only when *every* value the checker can infer
> fails. A typical cause here is a tuple shape that changed in one function, say from
> `{:ok, day}` to `{:ok, day, line}`, while a pattern elsewhere still expects the old shape.

---

## Exercise 1.6: `Report.week_of/1` and `Report.summarize/2`

```sh
cp ../docs/tutorial/01-tests/time_tracker/report_test.exs test/time_tracker/
mix test --only describe:"week_of/1" --only describe:"summarize/2"
```

Expect a compile error at first: the test builds a `%Report{}`.

`summarize(days, period)` returns
`%Report{period: range, by_description: %{desc => minutes}, by_day: %{date => minutes}, total: minutes}`.
Days outside the period are ignored.

Concepts to refresh:
- `Date.range/2`, and `date in range`. `in` works on any enumerable and uses
  `Enumerable.member?/2`, which is constant-time for a date range.
- `Date.beginning_of_week/2` and `end_of_week/2` with `:sunday` (task 0.9)
- `Enum.reduce/3` over days, then over activities, with the report struct as the accumulator
- `Map.update/4`, and struct update syntax `%{report | total: ...}`. What happens if you
  misspell a field in the update syntax?

## Exercise 1.7: `Report.format_minutes/1` and `Report.format/1`

```sh
mix test --only describe:"format_minutes/1" --only describe:"format/1"
```

The `format/1` test pins the exact layout. Make yours match it character for character. When it
fails, read ExUnit's diff of the `left` and `right` strings.

Concepts to refresh:
- `div/2` and `rem/2`, and `String.pad_leading/3` / `pad_trailing/3`
- heredocs (`"""`) with interpolation, and `Enum.map_join/3`
- sorting: maps have no defined order, so sort before printing. `Enum.sort/1` on `{key, value}`
  pairs sorts by key. **Dates need `Enum.sort_by(pairs, fn {d, _} -> d end, Date)`**: passing the
  `Date` module makes the sort use `Date.compare/2`. A plain `Enum.sort/1` puts `2026-02-01`
  before `2026-01-31`, for the same reason as in 1.5.
- `Calendar.strftime/2` for `Mon 2026-10-12`

## Exercise 1.8: The Mix task: back to the outer loop

```sh
mix test test/mix/tasks/tt.report_test.exs
```

Write `Mix.Tasks.Tt.Report` in `lib/mix/tasks/tt.report.ex`. This module is the **imperative
shell**. It's the only place that:
- reads the file (`File.read!/1`)
- asks the clock for today (`:calendar.local_time/0`, then `Date.from_erl!/1`)
- prints (`Mix.shell().info/1`), or fails (`Mix.raise/1` with the error lines)

Everything else it calls is pure.

Concepts to refresh:
- `use Mix.Task`, `@shortdoc` (what shows up in `mix help`), and `@impl Mix.Task`
- `OptionParser.parse!/2` with `strict:` options
- `Date.from_iso8601!/1`

**Check:** the acceptance test is green, *and* it works on a real file:

```sh
mix help tt.report
mix tt.report ~/path/to/your/time.md
```

---

## Design note: functional core, imperative shell; parse at the boundary

Look at what you've built:

```
            ┌──────────────── imperative shell ────────────────┐
 file ───▶  │ Mix.Tasks.Tt.Report: File.read!, clock, print    │ ───▶ terminal
            └───────┬────────────────────────────────▲─────────┘
                    │ text, today                    │ string
            ┌───────▼────────────── pure core ───────┴─────────┐
            │ Parser.parse ──▶ [%Day{}] ──▶ Report.summarize   │
            │        └── {:error, [{line, reason}]}  Report.format
            └──────────────────────────────────────────────────┘
```

- **The core is pure.** `Parser` and `Report` take data and return data. Their tests needed no
  files, clock or mocks, which is why there are about 50 fast `async: true` tests and only 3 slower
  ones for the shell.
- **The clock is I/O too.** Passing `today` in, rather than calling the clock inside the parser,
  is what made the year-rollover tests possible. It's the same move as passing storage in, and
  stage 2 does that next.
- **Parse at the boundary.** Untrusted text becomes `%Day{}`/`%Activity{}` *once*. `Report` never
  checks for a malformed line, a missing `out` or a backwards time, because those values can't
  reach it. In C# terms, `Parser.parse` returns something like `Result<IReadOnlyList<Day>, Errors>`,
  and the report takes only the success type.
- **Errors are values.** Because errors are data, the parser could *collect* all of them. An
  exception-based parser would have stopped at the first.

In stage 2 the shell gains storage, and the core shouldn't change at all. Watch whether it does.

---

## Done with stage 1

- [ ] all 53 stage 1 tests, plus your own, pass: `mix test`
- [ ] `mix format --check-formatted` and `mix credo --strict` are clean
- [ ] `mix tt.report` works on a real time log of yours
- [ ] you've decided the "only `out`" case and written a test for it
- [ ] committed on `2026-10`

**Next:** tell me when you're done (or stuck), and I'll review your code for idiom and design
before we start stage 2.
