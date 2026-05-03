# NBPR

Nerves Binary Package Repository — a curated Hex repo for distributing Buildroot-built target packages to Nerves firmware projects.

See `PLAN.md` for current status and `CLAUDE.md` for scope and design context.

## Layout

- `nbpr/` — the `:nbpr` library (the `NBPR.BrPackage` macro and Mix tasks).
- `packages/` — per-package mix projects (created via `mix nbpr.new <name>`).
- `scripts/` — cross-package orchestration.
