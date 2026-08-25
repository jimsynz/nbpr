defmodule NBPR.JpegTurboTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.JpegTurbo.__nbpr_package__()

    assert pkg.module == NBPR.JpegTurbo
    assert pkg.name == :jpeg_turbo
    assert pkg.version == 1
    assert pkg.br_package == "jpeg-turbo"
    assert pkg.description == "SIMD-accelerated JPEG codec providing the libjpeg API"
    assert pkg.homepage == "https://libjpeg-turbo.org/"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
