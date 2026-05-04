# Contributing to NBPR

Thanks for your interest. NBPR is small, focused, and actively
maintained — contributions are welcome via GitHub PRs.

## What you might be here to do

- **Add a new Buildroot package** — see the dedicated guide:
  [How to add a Buildroot package to NBPR](docs/howto/add-a-buildroot-package.md).
  This is the most common contribution and the one the rest of this
  document is aimed at.
- **Fix a bug or improve the library** — open an issue first if the
  change is non-trivial. Spike PRs welcome for small fixes.

More how-to guides (adding a daemon, adding a kernel module, bumping a
package's version, diagnosing a failed build) will land alongside this
one as the docs site fills out.

## Workspace setup

    git clone https://github.com/jimsynz/nbpr.git
    cd nbpr
    MIX_TARGET=rpi4 mix deps.get
    cd nbpr && mix test

The workspace is a flat monorepo, not an umbrella. The library lives at
`nbpr/`; the binary packages live at `packages/nbpr_*/`. A workspace
`mix.exs` at the root pulls everything together so `mix nbpr.build`
can resolve a real Nerves environment.

You can substitute any target you have hardware for; `rpi4` is just a
common choice. The only restriction is that the target must be in the
workspace `mix.exs` `deps()` list — add it there if not.

## Conventions

- **Commit messages** — Conventional Commits format:
  `type(scope): description`. Common types: `improvement` (new feature
  or enhancement), `fix`, `docs`, `chore`. Use backticks for code
  identifiers.
- **No `--no-verify` on commits.** Hooks exist for a reason; if one
  fails, fix the underlying issue.
- **No co-authorship trailers** on commits.
- **British/NZ English** in narrative prose (colour, behaviour,
  organisation). American spellings are fine when an external API uses
  them.
- **Don't merge your own PRs without review** unless explicitly
  authorised. Frank Hunleth and James Harton are the primary
  reviewers — significant design changes warrant a chat before code.

## CI expectations

Every PR runs the build matrix: every package × every target. A
successful build means each package builds clean against each target
system. The matrix is fast for cached packages (GHCR cache hit) and
slow for fresh ones (full Buildroot run, ~3-5 min per matrix entry).

CI also runs the test suite for the `:nbpr` library and each package's
smoke test. Compile must be clean with `--warnings-as-errors`.

## Releases

You don't release packages manually. After your PR merges to `main`:

1. The build matrix runs.
2. On success, an auto-release workflow detects packages whose local
   `@version` is ahead of Hex.
3. For each, it creates a `nbpr_<name>-v<version>` tag and the release
   workflow publishes to Hex.

To release a new package, just merge it with the right `@version` set
in its `mix.exs`. The pipeline handles the rest.

## Reporting bugs

GitHub Issues. Useful things to include:

- The package name and version you were using.
- The Nerves target and system version (`MIX_TARGET`, the system
  app's version).
- The full error output if there was one.
- Whether the failure is reproducible from a clean checkout.

For build failures, the Buildroot logs are usually the most useful
artefact. They live under `~/.local/share/nerves/nbpr/build/<system>-<br-version>/`
after a `mix nbpr.build` run; attach the output of the failing
Buildroot step.

## Licence

By contributing you agree that your contributions are licensed under
the same Apache-2.0 licence as the rest of the project.
