# Package versioning

Every `:nbpr_*` package mirrors the version of the Buildroot package it
wraps. Buildroot's versions aren't semantic versions, and hex.pm only
takes semantic versions, so each package coerces one into the other.

`NBPR.Version` is the single statement of these rules. A package can't
call it — Mix evaluates a project before any dependency exists — so each
`mix.exs` carries the coercion inline, generated from
`NBPR.Version.normalise_version_source/0`. A workspace test asserts the
copies haven't drifted.

## What hex.pm accepts

A version reaches hex.pm only if it is exactly `MAJOR.MINOR.PATCH`, all
three numeric, with no leading zeros.

| Version | Result |
| --- | --- |
| `1.8.2` | published |
| `2.92` | rejected — `Version.parse/1` can't read it |
| `1.02.3` | rejected — semver forbids leading zeros |
| `3.1.4+1` | rejected — `version: build number not allowed` |
| `7.1.2-26` | accepted, but see below |

Two tempting escapes are both closed:

* **Build metadata** (`3.1.4+1`) is refused by the API outright. It
  couldn't order releases anyway — semver ignores build metadata when
  comparing, so `Version.compare("3.1.4+1", "3.1.4")` is `:eq`.
* **A pre-release** (`7.1.2-26`) parses, and hex.pm will store it, but it
  sorts *below* the release it was meant to supersede
  (`7.1.2-26 < 7.1.2`) and Hex's resolver skips pre-releases unless a
  requirement names one. A consumer on `~> 7.1` would never resolve it.

## The coercion

`@version` holds Buildroot's literal — that's what Renovate writes there,
and it's the version the artefact actually contains. The generated
`normalise_version/1` derives the Hex version from it at project-eval
time:

| Upstream | Hex | Why |
| --- | --- | --- |
| `1.8.2` | `1.8.2` | already three numeric components |
| `2.92` | `2.92.0` | padded (dnsmasq, chrony, libcap) |
| `34` | `34.0.0` | padded (kmod) |
| `2.03.31` | `2.3.31` | leading zeros stripped (lvm2) |
| `3.1.4.1` | `3.1.4` | fourth component dropped (libjpeg-turbo) |
| `7.1.2-26` | `7.1.2` | patchlevel dropped (ImageMagick) |
| `1.2.3-rc1` | `1.2.3-rc1` | left alone — not ours to reinterpret |

Only *numeric* trailing components are dropped. A non-numeric suffix is a
real pre-release, so the coercion passes it through and
`NBPR.Version.validate/1` names the problem rather than a silent rewrite
claiming an upstream release the artefact isn't.

## What dropping costs

Dropping is lossy, and the loss bites. When upstream moves only the
component that got dropped — `3.1.4.1` → `3.1.4.2`, or `7.1.2-26` →
`7.1.2-27` — the Hex version doesn't move. `mix nbpr.releasable` sees
nothing to release, and there is no way to publish the new package source.

Hex has three numeric positions and uses all three for ordering. It has
no packaging-revision field, the way Debian has `-N` and Alpine has `-rN`.
So there is nowhere for an nbpr-side revision to go either: a package
whose upstream version already fills all three positions has no free slot
for a rebuild.

This blocks less than it first appears. An artefact tarball is addressed
by a cache key over the package version, system, system version and build
options, and carries no Elixir — so **artefact-only changes need no Hex
release**: rebuild, re-push under the same key. Only a change to a
package's *Elixir* source (metadata, daemons, `kernel_modules`) needs a
version to move.

The way out, when it's needed, is to decouple the Hex version from
upstream entirely and keep the upstream version in package metadata. Not
a cleverer encoding — there isn't one. [Decoupling](#decoupling) below is
that mechanism.

## Decoupling

Some upstream versions aren't awkward, they're unusable. Buildroot pins
`socketcand` to a git-describe snapshot:

    SOCKETCAND_VERSION = 0.6.1-103-g6dd5d33d4645ab221e8cd265c08607366e21ddf1

No coercion rescues that. Dropping the suffix would claim `0.6.1`, a
release from 2019 that the artefact is 103 commits past — the silent lie
`hex_version/1` exists to avoid. Keeping it parses, but as a pre-release,
which per the table above no `~>` requirement will ever resolve. There is
no third option: the version has to stop mirroring upstream.

A package declares that by naming Buildroot's literal in its metadata:

```elixir
use NBPR.BrPackage,
  version: 1,
  br_package: "socketcand",
  upstream_version: "0.6.1-103-g6dd5d33d4645ab221e8cd265c08607366e21ddf1",
  ...
```

`@version` in its `mix.exs` is then **nbpr's own**, starting at `0.1.0`,
and moves on nbpr's terms — which restores the patch slot the rest of the
catalogue lacks. `mix nbpr.new` emits both halves when it reads a version
hex.pm can't hold, so there's nothing to assemble by hand.

### What the upstream version still does

It joins the **artefact cache key**. That isn't decoration: a decoupled
package's Hex version can sit perfectly still while Buildroot moves to a
newer snapshot, and without this input the key wouldn't move either and a
stale tarball would be served for new sources. It is also recorded in the
artefact's `manifest.json` and rendered by `mix nbpr.inspect`.

It deliberately stays *out* of the tarball name and the OCI tag, which
keep using the Hex version — those are handles, and a 48-character
git-describe string in them buys nothing a manifest reader can't get.

The input is optional, and omitted from the key's encoding when absent, so
every artefact published before decoupling existed keeps its key.

### The cost

Two versions to bump instead of one, and Renovate can't help with the
second: its versioning schemes can't order a git-describe string, and the
`buildroot-package` datasource's regex captures only the leading
`[\d.]+`, which would silently report `0.6.1`. A decoupled package
therefore gets **no Renovate manager** — when Buildroot moves, bump
`upstream_version:` and `@version` together by hand.

Reach for this only when the alternative is not shipping the package.
Mirroring upstream is what makes a `:nbpr_*` version mean something
without looking it up.

## Adding a package with an awkward version

Nothing to do. `mix nbpr.new` writes Buildroot's literal into `@version`
and generates the coercion alongside it. If upstream's shape isn't one of
the rows above, the generator decouples the two as described above — and
if it's a shape that *should* coerce but doesn't, the workspace test fails
with the reason and the coercion needs a new rule in `NBPR.Version`, not a
hand-edited version in the package.
