# NBPR

Nerves Binary Package Repository — a curated Hex repo for distributing Buildroot-built target packages to Nerves firmware projects.

This workspace is **pre-spike**. See `PLAN.md` for the implementation plan and `CLAUDE.md` for design context.

## Layout

- `nbpr/` — the `:nbpr` library (the `NBPR.BrPackage` macro and Mix tasks).
- `packages/` — per-package mix projects (created via `mix nbpr.new <name>`).
- `scripts/` — cross-package orchestration.
