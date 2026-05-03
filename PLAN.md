# NBPR

**Status (2026-05-04):** The spike is complete bar one runtime check (see Outstanding). Source-build path validated end-to-end on macOS host across rpi4/rpi5/bbb. `mix nbpr.fetch` falls back to source-build when no prebuilt artefact is published, auto-shimming the system source from GitHub for users on Hex `nerves_system_*` deps. CI matrix auto-discovers `packages/nbpr_*/` and builds + publishes (package × target × system_version) to GHCR for the eight popular Nerves systems (rpi0, rpi0_2, rpi3, rpi3a, rpi4, rpi5, bbb, x86_64); the test matrix is similarly auto-discovered. `mix nbpr.new` reads the workspace's BR pin and pre-fills version, SPDX-validated licences, homepage, and a starter description from the BR tree. Catalogue: `:nbpr_dnsmasq`, `:nbpr_htop`, `:nbpr_iperf3`, `:nbpr_jq`. Hex publish workflow drafted but pending first tag.

For scope, conventions, and design decisions see `CLAUDE.md`.

## Outstanding

- **QEMU smoke test.** Boot a minimal Nerves image with a daemon-bearing package (`:nbpr_dnsmasq` is the obvious candidate) under QEMU and confirm the daemon actually runs end-to-end. The build and overlay paths are validated; runtime behaviour on an emulated target hasn't been exercised yet.

## Hex publish bootstrap (one-time)

Before tagging the first release:

1. Hex.pm `nbpr` organisation exists with the publishing user as a member (paid hex.pm org subscription).
2. `HEX_API_KEY` GitHub Actions secret is set, owned by a user with publish access to the `nbpr` org.
3. Publish order matters — `:nbpr_*` packages depend on `:nbpr`, so tag `nbpr-v0.1.0` first to land the library on public Hex.pm, then tag `nbpr_jq-v1.8.1` etc. to publish to the `nbpr` org.
