# Refreshing Elixir: building a time tracker

A staged tutorial for an engineer who already knows functional programming, Erlang, and (rusty)
Elixir. We build one application, a **time tracker**, and grow it through six stages. Each stage
introduces one storage idea and the Elixir/OTP concepts that come with it. The rework between
stages is deliberate: refactoring a working program under green tests is part of the lesson.

## How each stage works

- **You write the code; I coach.** Each exercise comes with a short concept refresher and one or
  more **failing ExUnit tests**. You make them pass, then I review the result for idiom and design.
- **Test-first.** Run each test and watch it fail before you write the implementation. A test that
  has never been red proves nothing.
- **Baseline before changing.** Start each stage on a green suite and finish it on a green suite.
  Commit at least once per exercise.

## The domain

You record your day in a flat markdown file:

```markdown
# 14-Oct
0800 email and planning
0915 code review
1200 lunch
1245 pairing on parser
1730 out

# 15-Oct
0830 standup
0845 design session
1700 out
```

- An **h1 header** holding a `dd-MMM` date starts a day.
- Each record under it is `hhmm description`. `hhmm` is the activity's **start time**, and the
  activity runs until the next record starts.
- **`hhmm out`** ends the day's last activity. It isn't an activity itself.
- The header has **no year**, so we infer one: use the current year, unless that would put the date
  in the future, in which case use the previous year. (On 2-Jan-2027, a header of `30-Dec` means
  30-Dec-2026.)
- Later, records gain **extra fields** (work/home, project, and so on). The syntax is still to be
  decided, and choosing it is one of your design decisions in stage 2.

There are two user tasks:

1. **Add** one or more days of time, parsed into **activities**.
2. **Report**: summarize how you spent your time over a period, by default this week.

## The stages

### Stage 0: Setup ([00-setup.md](00-setup.md))

Install a pinned Erlang/OTP and Elixir with mise, generate the Mix project, and relearn the daily
tools: `mix test`, `mix format`, Credo, and IEx. Ends with a green default test and a first commit.
There's no domain code yet.

### Stage 1: No storage, so the markdown file is the database

Every command re-reads and re-parses the markdown file. This is where most of the core language
comes back:

- binaries and string pattern matching (`<<h::binary-size(2), m::binary-size(2), " ", rest::binary>>`
  versus `String` functions versus `Regex`)
- structs (`%Activity{}`, `%Day{}`) with `@enforce_keys` and typespecs
- `Date`, `Time` and `Duration` from the standard library, including the year-inference rule
- errors as values: `{:ok, _}` / `{:error, reason}` and `with` chains; malformed lines are reported
  with line numbers, not crashed on
- `Enum` and `Stream` (reading a file lazily with `File.stream!/1`), `Enum.chunk_while/4` to split
  lines into days, and `Enum.group_by/3` and `Enum.reduce/3` for the report
- doctests, `describe` blocks, and test tags
- a thin command-line entry point (a Mix task first, an escript optionally), with `OptionParser`

Deliverable: `mix tt.report --from 2026-10-12 --to 2026-10-18` prints a per-description summary
straight from the markdown file.

### Stage 2: A serialized file store, and the `Storage` seam

"Add" now means parsing markdown once and storing the activities. Stage 2 introduces:

- a **behaviour** (`@callback`) named `TimeTracker.Storage`, with the parser and report written
  against it. This is the seam every later stage plugs into.
- a file backend using `:erlang.term_to_binary/1` and `binary_to_term/2` (with the `:safe`
  option, and why it matters), then a JSON backend using the built-in `JSON` module, so you can
  compare the two formats
- deduplication: what happens when you add the same day twice? You decide the rule.
- **extra fields** (work/home, project). Adding them means migrating data that was already stored
  in the old shape, a real-world refactoring problem.
- configuration through `config/config.exs` and `Application.get_env/3`, plus dependency injection
  of the backend in tests

### Stage 3: An in-memory process (`Agent`, then `GenServer`)

The store becomes a long-lived process that loads from the file at start and writes back on change.

- processes, mailboxes and message passing, revisited from the Elixir side
- `Agent` first, as the minimal stateful process, then a hand-written `GenServer` so you see what
  the `Agent` was hiding (`handle_call` versus `handle_cast`, `init/1`, `terminate/2` and its
  limits)
- turning the project into an OTP **application**: a supervision tree, child specs, restart
  strategies, and what happens to in-memory state after a crash
- testing stateful code: `start_supervised!/1`, isolation between tests, `async: true` and when it
  is unsafe

### Stage 4: ETS and DETS

Replace or augment the process store with Erlang term storage.

- ETS table types (`:set`, `:bag`, `:ordered_set`) and why an `:ordered_set` keyed by date makes
  range reports cheap
- `:ets.select/2` and match specifications (`:ets.fun2ms/1`, and when to reach for it)
- table ownership: the owning process dies, the table dies, and what that means for your
  supervision tree
- DETS for persistence, its limits, and comparing it with stage 2's file store
- Erlang interop in general: charlists versus binaries, and calling `:module.function`

### Stage 5 (optional): SQLite via Ecto

A real database behind the same `Storage` behaviour.

- `ecto_sqlite3`, `Ecto.Repo`, and migrations
- schemas and **changesets**: validation at the boundary, so the interior works only with valid data
- `Ecto.Query` for date-range reports, with grouping and aggregation pushed into SQL
- the SQL sandbox for concurrent, isolated tests
- a final look back: the same report test suite, passing against five storage backends

## Conventions

- The Mix project lives in [`time_tracker/`](../../time_tracker) at the repo root. Toolchain
  versions are pinned in the repo-root `mise.toml`.
- These tutorial chapters are in `docs/tutorial/`, one file per stage.
