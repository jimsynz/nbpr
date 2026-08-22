# nbpr_vorbis_tools

> Command-line player, encoder and decoder for Ogg Vorbis.

[`vorbis-tools`](https://xiph.org/vorbis/) packaged for Nerves. Tracks the
upstream Buildroot `vorbis-tools` package — this release wraps **1.4.3**.

Licence: GPL-2.0-only.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_vorbis_tools, "~> 1.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.


## What's in it

Six binaries, on `PATH` at boot, so `System.cmd/2` finds them by name:

| Binary          | What it does                                        |
| --------------- | --------------------------------------------------- |
| `oggenc`        | encode WAV/AIFF/raw to Ogg Vorbis                   |
| `oggdec`        | decode Ogg Vorbis to WAV or raw                     |
| `ogg123`        | play or transcode a stream, locally or over HTTP    |
| `ogginfo`       | report bitrate, channels, comments, stream problems |
| `vorbiscomment` | read and write Vorbis comment tags                  |
| `vcut`          | split a stream at a sample position, no re-encode   |

For example:

```elixir
{_output, 0} = System.cmd("oggenc", ["-q", "6", "-o", "/data/clip.ogg", "/data/clip.wav"])
{info, 0} = System.cmd("ogginfo", ["/data/clip.ogg"])
```


## Dependencies

Buildroot's vorbis-tools `select`s libao, libogg, libvorbis and libcurl
unconditionally, and no Nerves system ships any of them. An nbpr artefact
carries only its own Buildroot files-list, so each arrives as its own
package:

- [`nbpr_libao`](../nbpr_libao) — audio output, for `ogg123`
- [`nbpr_libogg`](../nbpr_libogg) — the container format
- [`nbpr_libvorbis`](../nbpr_libvorbis) — the codec
- [`nbpr_libcurl`](../nbpr_libcurl) — HTTP streaming, for `ogg123`

They come in automatically with this package. Note that libcurl on a stock
Nerves system has no CA bundle to verify HTTPS against — see that
package's README.


## ogg123 cannot reach a speaker yet

`ogg123` outputs through libao, and libao finds its output plugins by
`opendir` on a path fixed at build time (`/usr/lib/ao/plugins-4`) — a path
nbpr's priv-dir install doesn't populate. The ALSA plugin is therefore
invisible at runtime, leaving only libao's built-in file drivers:

```elixir
# writes a file — fine
System.cmd("ogg123", ["-d", "wav", "-f", "/data/out.wav", "/data/clip.ogg"])

# wants a speaker — no driver, fails
System.cmd("ogg123", ["/data/clip.ogg"])
```

[`nbpr_libao`](../nbpr_libao) has the detail and what a fix needs. The other
five binaries are unaffected — none of them touches libao.


## Not available on musl targets

`x86_64` is the one musl system NBPR builds for, and vorbis-tools doesn't
compile there. It vendors a copy of GNU `getopt`, guarded on
`__GNU_LIBRARY__` — which musl doesn't define — so the compiler sees K&R
declarations like `char *getenv ();`. GCC 15 defaults to C23, where `()`
means *no* parameters rather than "unspecified", and the build fails with
`too many arguments to function 'getenv'`.

The package declares this rather than failing late: `x86_64` is left out of
the prebuild matrix, and a source build for it stops with an explanation
instead of a Buildroot compile error. A real fix means Buildroot carrying
`-std=gnu17` for this package or patching the vendored getopt.

Every other target is glibc and unaffected.


## Configuration

Build options can be overridden in your app's `config/target.exs`:

    config :nbpr_vorbis_tools, build_opts: [flac: true]

`flac` builds against libFLAC, so `oggenc` takes `.flac` input directly and
`ogg123` plays it. It's off by default, matching Buildroot. Turning it on
means adding the library to your own dependencies too:

    {:nbpr_flac, "~> 1.0", organization: "nbpr"}

Without it, `mix nbpr.fetch`'s shared-library check will tell you
`libFLAC.so.14` is missing from the firmware rather than letting you find
out on the device.

Buildroot's vorbis-tools also picks up Speex and Opus input when those
packages are enabled. Neither is exposed here: nothing packages `libspeex`
or `libopusfile` for NBPR yet, so the option could only produce an artefact
with sonames nothing in the firmware resolves.

Build options are part of the artefact cache key, so a non-default value
has no prebuilt artefact to match and falls to a source build.

Source: <https://github.com/jimsynz/nbpr>.
