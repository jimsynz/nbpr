# nbpr_librespot

> An open source client library for Spotify.

[`librespot`](https://github.com/librespot-org/librespot) packaged for Nerves.

**This is a vendored package.** librespot is not in Buildroot mainline, so this
package carries its own Buildroot external tree under `priv/buildroot` and NBPR
builds it from there. Everything else about it works the way a mainline package
does.

Licence: MIT. The build tracks librespot **0.8.0**.

## Read this before you ship it

A Spotify **Premium** account is required, and the librespot project says of
itself: *"Using this code to connect to Spotify's API is probably forbidden by
them. Use at your own risk."* That sentence is the whole of the decision, and it
is yours and not this package's. The licensed alternative is Spotify's Embedded
SDK, which needs a company agreement and per-device certification.

## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_librespot, "~> 0.8", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html).

Source: <https://github.com/jimsynz/nbpr>.
