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

## Design principles

There's no formal Elixir equivalent of SOLID. The community has, though, largely converged on a
handful of principles, and each comes with a stated reason. Every chapter has a **Design note**
covering the principle that first matters in that stage.

1. **The OTP design principles.** Separate the generic (a behaviour such as `GenServer`) from the
   specific (your callback module), and structure the system as supervision trees in which
   unanticipated failures crash and restart rather than being defensively handled. See the Erlang
   *OTP Design Principles* guide, and Joe Armstrong's thesis *Making reliable distributed systems in
   the presence of software errors* (2003) for the reasoning.
2. **Use modules to organize code and processes to model runtime concerns.** A process is not an
   object. Use one for concurrency, failure isolation, or state that lives over time, never just to
   group code. (Saša Jurić, *To spawn, or not to spawn?*)
3. **Functional core, imperative shell.** The domain is pure functions over plain data, and I/O,
   state and processes stay at the edges. (Gary Bernhardt; Gray and Tate, *Designing Elixir Systems
   with OTP*.)
4. **Explicit boundaries with a small public API.** Group related modules behind one public module
   (what Phoenix calls a "context"), and don't let callers reach into its internals.
5. **Errors as values at boundaries, assertive code inside.** Expected failures come back as
   `{:ok, _}` / `{:error, _}`. Inside, pattern-match on the shape you expect and let anything else
   crash.

The closest thing to an official list is the **anti-patterns guides** in the Elixir documentation
(code, design, process and macro anti-patterns), each written as problem, example, refactoring.

Rough SOLID mapping: **S**, small modules and one process per runtime concern; **O**, protocols and
behaviours; **L**, behaviour contracts plus typespecs; **I**, small behaviours; **D**, depend on a
behaviour and inject the implementation.

Still contested: how big contexts should be, umbrella apps versus one app, whether Ecto schemas
belong in the domain, and how far to lean on the new type system versus typespecs and Dialyzer.

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

**Design note: the application is the unit of composition.** Even without `--sup`, `mix new`
generates an OTP *application*, which is what gets started, stopped, depended on and released.

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

**Design note: functional core, imperative shell; parse at the boundary.** The parser turns
untrusted text into valid structs or `{:error, reason}` exactly once, and the report code never sees
a malformed line. The Mix task is the only code that touches files or prints.

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

**Design note: dependency inversion with behaviours, and explicit boundaries.** The domain depends
on the `Storage` contract, not on a backend. We'll also compare **behaviours** (polymorphism by
module) with **protocols** (polymorphism by data type) and say when each fits. A small public
`TimeTracker` API is the boundary that the CLI calls.

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

**Design note: processes model runtime concerns, not code organization; generic versus specific.**
The store gets a process because its state lives over time, and the parser and report stay plain
modules. Writing the `GenServer` by hand shows OTP's split between the generic part (the behaviour)
and the specific part (your callbacks). Crashing a supervised store on purpose shows "let it crash"
working, and what it costs.

### Stage 4: ETS and DETS

Replace or augment the process store with Erlang term storage.

- ETS table types (`:set`, `:bag`, `:ordered_set`) and why an `:ordered_set` keyed by date makes
  range reports cheap
- `:ets.select/2` and match specifications (`:ets.fun2ms/1`, and when to reach for it)
- table ownership: the owning process dies, the table dies, and what that means for your
  supervision tree
- DETS for persistence, its limits, and comparing it with stage 2's file store
- Erlang interop in general: charlists versus binaries, and calling `:module.function`

**Design note: avoid unnecessary serialization through a single process.** A `GenServer` handles
one message at a time, so routing every read through it creates a bottleneck. ETS allows
concurrent reads while a process still owns the table's lifecycle, which separates *who owns the
state* from *who can read it*.

### Stage 5 (optional): SQLite via Ecto

A real database behind the same `Storage` behaviour.

- `ecto_sqlite3`, `Ecto.Repo`, and migrations
- schemas and **changesets**: validation at the boundary, so the interior works only with valid data
- `Ecto.Query` for date-range reports, with grouping and aggregation pushed into SQL
- the SQL sandbox for concurrent, isolated tests
- a final look back: the same report test suite, passing against five storage backends

**Design note: validation at the boundary, and where the database belongs (contested).** Changesets
are "parse at the boundary" applied to persistence. The open question is whether Ecto schemas
*are* the domain structs or a persistence edge that maps to and from the stage 1 structs. We'll
build it one way and argue the other.

## Conventions

- The Mix project lives in [`time_tracker/`](../../time_tracker) at the repo root. Toolchain
  versions are pinned in the repo-root `mise.toml`.
- These tutorial chapters are in `docs/tutorial/`, one file per stage.
