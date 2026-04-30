defmodule NBPR.RuntimeTest do
  use ExUnit.Case, async: true

  describe "on_nerves_target?/0" do
    test "returns false on the dev host" do
      refute NBPR.Runtime.on_nerves_target?()
    end
  end

  describe "modprobe!/1" do
    test "raises with non-zero exit and stderr included" do
      assert_raise RuntimeError, ~r/modprobe .* failed/, fn ->
        NBPR.Runtime.modprobe!("__nbpr_definitely_not_a_real_module__")
      end
    end
  end
end
