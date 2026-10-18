# Stage 0: Setup

**Goal:** a pinned, reproducible Erlang/OTP + Elixir toolchain, a generated Mix project with a green
test suite, formatter and Credo wired in, your IEx muscle memory back, and a first commit. There's
no domain code in this stage.

**Target versions** (the latest stable releases as of 2026-10-16):

| Tool | Version |
|---|---|
| Erlang/OTP | 29.1.2 |
| Elixir | 1.20.4 (built for OTP 29) |
| OS | Ubuntu 24.04 on WSL2 |

Work through the tasks in order. Each one ends with a **Check**: the observable result that tells
you the task is done. If a check doesn't match, stop and sort it out before moving on.

---

## Task 0.1: Install mise and activate it in zsh

[mise](https://mise.jdx.dev) is a per-project version manager (an asdf successor). It reads a
`mise.toml` and puts the pinned tool versions on your `PATH` whenever you're inside that directory.

```sh
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc
exec zsh
```

**Check:**

```sh
mise --version     # prints a 2026.x version
mise doctor        # "activated: yes", and no problems reported
```

## Task 0.2: Install Erlang's build dependencies

mise normally installs Erlang by **compiling it from source** (via kerl), which needs a C toolchain
and a few libraries. Install them first, even if your mise version ends up using a precompiled build;
having them there does no harm.

```sh
sudo apt update
sudo apt install -y build-essential autoconf m4 libncurses-dev libssl-dev \
  libssh-dev unzip xsltproc libxml2-utils
```

To skip the parts of OTP this project doesn't need (the wxWidgets GUI apps such as `:observer`'s
window, ODBC, and Java), and to build the Erlang docs so `h :ets` works in IEx, add this to
`~/.zshrc` before the next task:

```sh
export KERL_CONFIGURE_OPTIONS="--without-javac --without-wx --without-odbc"
export KERL_BUILD_DOCS=yes
```

Run `exec zsh` afterwards.

**Check:** `echo $KERL_CONFIGURE_OPTIONS` prints the options above.

> **Trade-off:** `--without-wx` means `:observer.start()` won't open its GUI. In stage 3 we can use
> the terminal alternative `:observer_cli`, or rebuild with wx (`libwxgtk3.2-dev`) if you'd like
> the GUI under WSLg.

## Task 0.3: Pin and install Erlang and Elixir for this repo

From the **repo root**:

```sh
cd ~/professional/projects/refresh-elixir-ai
mise use erlang@29.1.2
mise use elixir@1.20.4-otp-29
```

`mise use` installs each tool and writes it into `./mise.toml`. Erlang has to come first, and the
`-otp-29` suffix picks the Elixir build compiled against your OTP major version. **If Erlang
compiles from source, expect it to take 10–20 minutes.** That's a good time to eat dinner.

**Check:**

```sh
cat mise.toml
# [tools]
# erlang = "29.1.2"
# elixir = "1.20.4-otp-29"

elixir --version
# Erlang/OTP 29 [erts-...] ...
# Elixir 1.20.4 (compiled with Erlang/OTP 29)

erl -noshell -eval 'io:format("~s~n", [erlang:system_info(otp_release)]), halt().'
# 29
```

Also run `cd ~ && elixir --version`. It should fail with "command not found", unless you
deliberately pin a global version with `mise use -g`. The versions belong to this repo, not to your
machine.

## Task 0.4: Install Hex and Rebar

Hex is the package manager. Rebar3 builds Erlang dependencies, and Credo and Ecto later depend on
some of those.

```sh
mix local.hex --force
mix local.rebar --force
```

**Check:** `mix hex.info` prints Hex, Elixir and OTP versions with no error.

### Behind a TLS-inspecting proxy (a corporate network)

`mix hex.info` only prints local versions. Now check that Hex can reach hex.pm:

```sh
mix hex.info credo   # should list recent releases
```

If it fails with `{:tls_alert, {:unknown_ca, ...}}`, a proxy is re-signing HTTPS traffic. To
confirm:

```sh
echo | openssl s_client -connect hex.pm:443 -servername hex.pm 2>/dev/null \
  | openssl x509 -noout -issuer
# a corporate issuer (e.g. "Zscaler ...") rather than a public CA
```

IT usually installs the proxy's root CA into Ubuntu's system bundle, which is why `curl` and `apt`
work. **Hex doesn't use that bundle by default**: it checks against its own built-in CA list. Point
it at the system bundle:

```sh
mix hex.config cacerts_path /etc/ssl/certs/ca-certificates.crt
```

This is a Mix task, so run it in the shell. It **creates** `~/.hex/hex.config` for you. Don't create
or edit that file by hand: Hex evaluates it as Elixir terms, and if the file doesn't parse, every
Hex command crashes on startup. The setting lives under `~/.hex`, not the per-Elixir-version
`MIX_HOME`, so it survives Elixir upgrades. (An alternative is
`export HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt` in `~/.zshrc`.)

**Check:** `mix hex.info credo` lists recent releases.

## Task 0.5: Generate the Mix project

Create the project **in a subdirectory**. The repo root keeps the docs, `mise.toml`, README and
license, and `time_tracker/` is the application.

```sh
mix new time_tracker
cd time_tracker
```

Leave out `--sup` on purpose. In stage 3 you'll add the `Application` module and supervision tree
by hand, which teaches more than having them generated.

Take a short tour, and say out loud what each file is for:

| File | What to look at |
|---|---|
| `mix.exs` | `project/0` (app name, version, `elixir:` requirement), `application/0`, `deps/0` |
| `lib/time_tracker.ex` | `@moduledoc`, `@doc`, and the doctest example inside `hello/0` |
| `test/test_helper.exs` | `ExUnit.start()`, and nothing else yet |
| `test/time_tracker_test.exs` | `use ExUnit.Case`, `doctest TimeTracker`, one `test` |
| `.formatter.exs` | `inputs:` globs, the files `mix format` touches |
| `.gitignore` | Mix's own ignores (`_build/`, `deps/`, …), scoped to this subdirectory |

**Check:** `mix compile` reports `Generated time_tracker app`.

> **Design note: the application is the unit of composition.** You ran `mix new` without `--sup`,
> but you still got an OTP **application**. Look at `application/0` in `mix.exs`, then run
> `mix compile` and open `_build/dev/lib/time_tracker/ebin/time_tracker.app`. That generated
> resource file is what OTP actually loads. An application is the unit OTP starts and stops,
> that other applications depend on, and that a release bundles. It's the system-level counterpart
> of the module. Your own code, `:logger`, `:crypto` and later Credo and Ecto are all applications,
> and a running node is a set of them. In IEx (`iex -S mix`), `Application.started_applications()`
> lists them.
>
> The OO habit to unlearn: there's no `main` that wires everything together. Each application
> declares what it depends on and, optionally, a callback module that starts its supervision tree.
> OTP starts them in dependency order. You'll write that callback module in stage 3.

## Task 0.6: Red, then green

Running the stock tests is fine, but practising the red-green loop on something trivial is the
point here.

1. Run `mix test`. **Check:** `Result: 2 passed (1 doctest, 1 test)`.
2. Edit `test/time_tracker_test.exs` so the assertion expects `:mars` instead of `:world`.
3. Run `mix test`. **Check:** 1 failure. Read the whole failure report, and notice that ExUnit shows
   the `left` and `right` sides of the `==` and colours the diff.
4. Practise the focused-run flags:
   - `mix test test/time_tracker_test.exs:LINE` runs only the test at that line
   - `mix test --failed` reruns only what failed last time
   - `mix test --trace` runs tests synchronously with per-test output
5. Revert to `:world`. **Check:** `mix test` is green again.
6. Now break the **doctest** instead (change `:world` in the `iex>` example in
   `lib/time_tracker.ex`) and watch it fail, then revert. Doctests are executable documentation.

## Task 0.7: Formatter

```sh
mix format --check-formatted   # exits 0: generated code is already formatted
```

Deliberately mangle the indentation in `lib/time_tracker.ex`, then:

```sh
mix format --check-formatted   # exits non-zero, lists the file
mix format                     # fixes it
```

**Check:** `mix format --check-formatted` exits 0 again (`echo $?` prints `0`).

If your editor supports it, turn on format-on-save for `.ex`/`.exs` files.

## Task 0.8: Add Credo

Credo is the community linter: style, consistency, and some design smells.

1. Look up the current version: `mix hex.info credo`.
2. Add it to `deps/0` in `mix.exs`, for dev and test only, as a tool rather than a runtime
   dependency:

   ```elixir
   {:credo, "~> X.Y", only: [:dev, :test], runtime: false}
   ```

   Replace `X.Y` with the major.minor version you found.
3. `mix deps.get`
4. `mix credo gen.config` writes `.credo.exs`. Skim it, and notice the check categories.
5. `mix credo --strict`

**Check:** Credo reports no issues on the generated code. (If it reports one, such as a missing
`@moduledoc`, read the explanation with `mix credo explain <file>:<line>`, fix it, and rerun.)

## Task 0.9: IEx refresher

```sh
iex -S mix
```

Work through these and note anything that surprises you:

| Try | What it shows |
|---|---|
| `h Enum.chunk_while` | docs for any function (you'll use this one in stage 1) |
| `h :ets.new` | Erlang docs too, if `KERL_BUILD_DOCS` worked |
| `i "16-Oct"` then `i ~c"16-Oct"` | binary versus charlist, which matters for Erlang interop |
| `exports(String)` | everything a module exports |
| `TimeTracker.hello()` | your project code is loaded |
| `v()` / `v(-2)` / `v(n)` | previous results: `-` counts back, `n` is a prompt number[^v] |
| Edit `hello/0` to return `:mars`, then `recompile` and call it again | reload without restarting |
| `dbg(Enum.map([1, 2, 3], &(&1 * 2)))` | `dbg/1` prints the expression *and* its value; with a pipeline it shows each step |
| `~D[2026-10-16] \|> Date.day_of_week()` | the date sigil; you'll lean on `Date` a lot |
| `Date.shift(~D[2026-10-16], week: -1)` | `Date.shift/2` and durations, used for "this week" |

[^v]: `v()` = `v(-1)`; `v(0)` is an error. `v(n)` returns a *result*, not printed output, so it
    shows nothing for `h`/`i`/`exports` prompts. **Prefer binding** (`r = TimeTracker.hello()`):
    names don't shift.

Exit with `Ctrl-\` (or `Ctrl-C` twice). Revert any edits to `hello/0`.

Optionally, create `time_tracker/.iex.exs` with `alias` lines you'll want later. It runs at every
IEx start inside the project.

**Check:** you can answer, without looking: how do you get docs for a function, how do you reload
changed code, and what's the difference between `"abc"` and `~c"abc"`?

## Task 0.10: What's changed since you last wrote Elixir

You last wrote Elixir a few years ago. Skim the changelogs for the releases you missed (as of
2026-10, the official changelogs are linked from <https://hexdocs.pm/elixir/changelog.html>). The
changes that will come up in this tutorial:

- **The type system.** From Elixir 1.17 on, the compiler type-checks code using set-theoretic types
  and warns about provable type errors, such as calling a function with an argument that can never
  match. Treat those warnings as real.
- **`dbg/1`** (1.14): pipeline-aware debugging, replacing `IO.inspect` scattered through pipes.
- **The built-in `JSON` module** (1.18): no Jason dependency needed for basic encoding and decoding.
  You'll use it in stage 2.
- **`Duration` and `Date.shift/2` / `DateTime.shift/2`** (1.17): calendar arithmetic without
  hand-rolled second counting. You'll use them in stage 1.
- **`Mix.install/2`** (1.12): single-file scripts with dependencies, useful for quick experiments
  outside the project.

**Check:** you've written two or three notes in your own words (in `_laj/` if you like) about what's
new to you.

## Task 0.11: Commit

From the repo root, on branch `2026-10`:

```sh
git status   # expect: mise.toml, time_tracker/, docs/
git add mise.toml time_tracker docs
git commit -m "Stage 0: toolchain pinned with mise, Mix project generated"
```

**Check:** `git status` is clean, and `git show --stat HEAD` contains **no** `_build/` or `deps/`
paths. (If it does, the `.gitignore` scoping went wrong, so fix it before going further.)

---

## Done with stage 0

You're done when all of these are true:

- [x] `elixir --version` shows 1.20.4 / OTP 29 inside the repo, and nothing outside it
- [x] `mix test`, `mix format --check-formatted` and `mix credo --strict` are all green in `time_tracker/`
- [x] you've seen a test and a doctest go red and back to green
- [x] stage 0 is committed on `2026-10`

**Next:** once these are true, tell me and I'll write stage 1, checking every failing test I give you
against your own toolchain first.
