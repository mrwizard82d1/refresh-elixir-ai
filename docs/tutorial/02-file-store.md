# Stage 2: A serialized file store, and the `Storage` seam

> **Status:** only the design note is written. The exercises and failing tests come after stage 1.

## Design note: the Dependency Rule in Elixir

In *Clean Architecture*, Robert Martin's **Dependency Rule** says source-code dependencies point
inward: policy never depends on details such as storage, UI or frameworks. It rests on the
**Dependency Inversion Principle**, the D in SOLID. ("Inversion of control" is a related but
different term, usually used for frameworks calling your code.)

Elixir supports this with less ceremony than C# or Java. There are three levels, from lightest to
strongest.

### 1. The lightest form: the core doesn't call storage at all

In a functional language you often don't need an interface. The core takes data and returns data,
and the shell does all the I/O around it. Mark Seemann calls this the "impureim sandwich": impure,
then pure, then impure.

```elixir
# shell: read, call the pure core, write
def report(from, to) do
  with {:ok, days} <- storage().days_between(from, to) do
    {:ok, Report.summarize(days, from, to)}   # pure: no I/O, trivially testable
  end
end
```

`Report` and `Parser` from stage 1 don't reference storage at all, so the dependency arrow doesn't
exist rather than being inverted. This is the default habit in Elixir, and it's why stage 1 could
run with no storage.

You only need an inverted dependency (a "port") when the core has to decide *mid-computation* what
to fetch or store.

### 2. Ports and adapters with behaviours

When you do need a port, a **behaviour** is Elixir's interface, and the core owns the contract.
(This is a sketch. You'll design the real callbacks in this stage's exercises.)

```elixir
defmodule TimeTracker.Storage do              # the port, owned by the core
  @callback save_days([Day.t()]) :: :ok | {:error, term()}
  @callback days_between(Date.t(), Date.t()) :: {:ok, [Day.t()]} | {:error, term()}
end

defmodule TimeTracker.Storage.TermFile do      # an adapter: a detail
  @behaviour TimeTracker.Storage
  @impl true
  def save_days(days), do: ...
  @impl true
  def days_between(from, to), do: ...
end
```

The compiler warns when an adapter is missing a callback or marks a non-callback with `@impl`.
Typespecs, Dialyzer and the newer type checker cover argument types, though less strictly than a
C# interface does.

**Wiring it up.** Modules are values in Elixir, so injection is just passing an atom. There are
three common ways to do it. **Choosing one is your design decision in this stage.**

| Mechanism | Looks like | Trade-off |
|---|---|---|
| Pass it explicitly | `Tracker.add(md, storage: TermFile)` | Most explicit and easiest to test; a bit noisier at call sites |
| Application config | `config :time_tracker, storage: TermFile`, read with `Application.fetch_env!/2` | `config/runtime.exs` becomes your **composition root**. Config is global, though, which complicates `async: true` tests |
| A named process | The adapter is a `GenServer` registered under a name, and callers send it messages | The boundary is a *message protocol*. The adapter can be swapped, restarted by a supervisor, or moved to another node with callers unchanged (stage 3) |

The third option has no real equivalent in C# or Java. With processes and location transparency, a
port can be a runtime boundary as well as a compile-time one.

**Testing.** The community's position comes from José Valim's essay *Mocks and explicit
contracts*: only mock against an explicit contract, meaning a behaviour. His library **Mox**
enforces this by refusing to mock a module that has no behaviour. A hand-written in-memory adapter
works just as well and needs no dependency. Either way, the fake sits at the boundary.

### 3. Enforcing the dependency direction

C# has assembly references, and Elixir has similar options:

- **Separate OTP applications.** Put the core and each adapter in their own Mix project, either as
  an umbrella or as sibling "poncho" projects. If the core's `mix.exs` doesn't list an adapter as a
  dependency, the core can't call it. This is the closest match to separate assemblies, and the
  strongest enforcement.
- **The `boundary` library** gives compile-time errors when modules inside one application cross
  declared boundaries.
- **`mix xref graph`** shows the actual dependency graph, so you can check the arrows point the way
  you intended.

### Behaviours versus protocols

Both give polymorphism, but they dispatch on different things:

- A **behaviour** is polymorphism by *module*. The caller picks which implementation to call, as
  with the `Storage` adapters above. Use one for pluggable components.
- A **protocol** is polymorphism by *data type*. The dispatch follows the value's type, as with
  `String.Chars` or `Enumerable`. Use one when new data types should plug into existing code, for
  example a report renderer for different output formats.

### Where this goes in the rest of the tutorial

- Stage 1 built the pure core with no storage.
- Stage 2 introduces the `Storage` port and your choice of injection mechanism. A small public
  `TimeTracker` module is the boundary the CLI calls.
- Stages 3–5 are successive adapters (a GenServer, ETS/DETS, Ecto), each passing the same core
  test suite.

Supporting different storage needs gets more interesting in stage 3, where the adapter is a process
with its own lifecycle and failure behaviour, not just a different module.
