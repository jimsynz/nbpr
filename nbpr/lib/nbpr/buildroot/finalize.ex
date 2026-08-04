defmodule NBPR.Buildroot.Finalize do
  @moduledoc """
  Applies Buildroot's `target-finalize` cleanup to a harvested per-package
  target tree.

  ## Why this exists

  Buildroot doesn't stop packages installing headers, static archives, docs and
  manpages — it lets them, then deletes the lot in one `target-finalize` recipe
  at the end of a full build, stripping every binary in `$(TARGET_DIR)` on the
  way past.

  NBPR never reaches that step. It runs `<pkg>-dirclean`, `<pkg>` and
  `<pkg>-legal-info`, then harvests `per-package/<pkg>/target/` directly. That's
  deliberate — `target-finalize` first rsyncs *every* package into a shared
  `TARGET_DIR`, which would destroy the per-package scoping
  `NBPR.Buildroot.FilesList` exists to preserve — but it meant artefacts shipped
  unstripped binaries and static archives into a rootfs whose own files
  Buildroot had stripped.

  Measured on real artefacts: `nbpr_chrony` 1815 KB → 423 KB, `nbpr_libcap`
  508 KB → 60 KB, `nbpr_pps_tools` 103 KB → 37 KB.

  So this reproduces the same recipe against one package's harvested tree.
  Because it runs *after* the files-list copy, its removals overlap the narrower
  runtime filter in `FilesList` (and that filter's shell twin in the container
  backend): the filter avoids copying the obvious cases, this catches the rest.
  That filter stays — besides pre-filtering, it's the only thing cleaning
  `staging/`, which nothing here touches.

  ## Shape

  The whole thing is emitted as one POSIX shell fragment, and every decision
  that depends on Buildroot's configuration is made *in* that shell by grepping
  the resolved `.config`. That's not squeamishness about Elixir — it's that the
  config only becomes meaningful after `make olddefconfig`, and for the
  container backend the resolved file lives inside the container where Elixir
  can't reach it. Deciding in shell keeps one definition of "finalize" for both
  backends instead of one per backend.

  ## What it doesn't do

  `staging/` is left alone, matching Buildroot — whose `staging-finalize` does
  nothing but create a symlink. Headers, `.la` files and unstripped libraries
  all survive there by design, because the point of the staging slice is
  cross-compiling consumer NIFs against the package. What trimming staging does
  get comes from `FilesList`, not here.

  ## Stripping

  Gated on `BR2_STRIP_strip=y`, which is what decides whether Buildroot's own
  `STRIPCMD` is `strip` or `/bin/true`. Buildroot's exclusions are reproduced,
  and they matter:

    * `*.ko` — kernel modules stop working if stripped like an executable, and
      NBPR ships them (`kernel_modules:` packages).
    * `ld-*.so*`, `libpthread*.so*` — `--strip-debug` only, so valgrind and
      pthread-aware gdb keep working.

  `BR2_STRIP_EXCLUDE_DIRS` / `BR2_STRIP_EXCLUDE_FILES` are deliberately *not*
  implemented. No stock Nerves system sets either, and translating them into
  `find` clauses is the kind of code that looks right and silently strips
  something it shouldn't. Instead, if a system sets one, stripping is skipped
  entirely with a warning — safe, obvious, and a clear prompt to implement it
  properly when something actually needs it.
  """

  # Buildroot: STRIPCMD = $(TARGET_CROSS)strip --remove-section=.comment
  #                       --remove-section=.note
  @strip_flags "--remove-section=.comment --remove-section=.note"

  # Buildroot strips everything executable or `*.so*` except these.
  @strip_exclude ~w(libpthread*.so* ld-*.so* *.ko)

  # These keep their symbol tables and lose only debug info.
  @strip_debug_only ~w(ld-*.so* libpthread*.so*)

  # Removed unconditionally by target-finalize, in its order.
  @remove_always ~w(usr/include usr/share/aclocal usr/lib/pkgconfig
                    usr/share/pkgconfig usr/lib/cmake usr/share/cmake
                    usr/lib/rpm usr/doc usr/man usr/share/man usr/info
                    usr/share/info usr/share/doc usr/share/gtk-doc)

  # Removed unless the owning package is in the firmware. The resolved config
  # carries the whole base system, so these answer "is bash in this firmware".
  @remove_unless [
    {"BR2_PACKAGE_GDB", ~w(usr/share/gdb)},
    {"BR2_PACKAGE_BASH", ~w(usr/share/bash-completion etc/bash_completion.d)},
    {"BR2_PACKAGE_ZSH", ~w(usr/share/zsh)}
  ]

  @doc """
  Returns a POSIX shell fragment that finalizes `target_dir`.

  `host_bin_dir` is the per-package `host/bin` holding the cross `*-strip`, and
  `config_path` the resolved Buildroot `.config` — both as seen by whoever runs
  the fragment, so the container backend passes container paths and the shell
  backend host ones.
  """
  @spec script(Path.t(), Path.t(), Path.t()) :: String.t()
  def script(target_dir, host_bin_dir, config_path)
      when is_binary(target_dir) and is_binary(host_bin_dir) and is_binary(config_path) do
    """
    # === Buildroot target-finalize equivalent — see NBPR.Buildroot.Finalize ===
    nbpr_target=#{q(target_dir)}
    nbpr_config=#{q(config_path)}

    nbpr_cfg_y() { grep -qx "$1=y" "$nbpr_config" 2>/dev/null; }
    nbpr_cfg_set() { grep -q "^$1=\\"..*\\"$" "$nbpr_config" 2>/dev/null; }

    #{removals(target_dir)}

    #{stripping(host_bin_dir)}
    """
  end

  defp removals(target_dir) do
    t = &q(Path.join(target_dir, &1))

    conditional =
      Enum.map_join(@remove_unless, "\n", fn {symbol, paths} ->
        "nbpr_cfg_y #{symbol} || rm -rf #{Enum.map_join(paths, " ", t)}"
      end)

    """
    rm -rf #{Enum.map_join(@remove_always, " ", t)}

    #{conditional}

    # Buildroot keeps split debug info only when debugging is on and stripping
    # is off: `ifneq ($(BR2_ENABLE_DEBUG):$(BR2_STRIP_strip),y:)`.
    if nbpr_cfg_y BR2_ENABLE_DEBUG && ! nbpr_cfg_y BR2_STRIP_strip; then
      :
    else
      rm -rf #{t.("lib/debug")} #{t.("usr/lib/debug")}
    fi

    find #{t.("usr/lib")} #{t.("usr/share")} \\
      -name '*.cmake' -type f -delete 2>/dev/null || true

    find #{t.("lib")} #{t.("usr/lib")} #{t.("usr/libexec")} \\
      \\( -name '*.a' -o -name '*.la' -o -name '*.prl' \\) -type f -delete 2>/dev/null || true

    rmdir #{t.("usr/share")} 2>/dev/null || true\
    """
  end

  defp stripping(host_bin_dir) do
    """
    if ! nbpr_cfg_y BR2_STRIP_strip; then
      echo "[nbpr] BR2_STRIP_strip is not set; leaving binaries unstripped, as Buildroot would" >&2
    elif nbpr_cfg_set BR2_STRIP_EXCLUDE_DIRS || nbpr_cfg_set BR2_STRIP_EXCLUDE_FILES; then
      # Honouring these means generating find clauses from config strings, which
      # NBPR.Buildroot.Finalize deliberately doesn't do. Skip rather than risk
      # stripping something the system asked us to leave alone.
      echo "[nbpr] WARNING: BR2_STRIP_EXCLUDE_{DIRS,FILES} is set; skipping stripping entirely" >&2
    else
      # Directory quoted, glob left bare so the shell actually expands it.
      nbpr_strip=$(ls #{q(host_bin_dir)}/*-strip 2>/dev/null | head -1 || true)
      if [ -z "$nbpr_strip" ] || [ ! -x "$nbpr_strip" ]; then
        echo "[nbpr] WARNING: no cross strip under #{host_bin_dir}; shipping unstripped binaries" >&2
      else
        # Everything executable or shared, minus the three Buildroot spares.
        find "$nbpr_target" -type f \\( -perm /111 -o -name '*.so*' \\) \\
          -not \\( #{name_clauses(@strip_exclude)} \\) \\
          -print0 | xargs -0 -r "$nbpr_strip" #{@strip_flags} 2>/dev/null || true

        # Debug symbols only, so gdb and valgrind keep working.
        find "$nbpr_target" -type f \\( #{name_clauses(@strip_debug_only)} \\) \\
          -print0 | xargs -0 -r "$nbpr_strip" --strip-debug 2>/dev/null || true
      fi
    fi\
    """
  end

  defp name_clauses(patterns), do: Enum.map_join(patterns, " -o ", &"-name #{q(&1)}")

  defp q(s), do: "'" <> String.replace(s, "'", ~S('\'')) <> "'"
end
