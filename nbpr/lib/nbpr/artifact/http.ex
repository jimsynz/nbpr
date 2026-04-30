defmodule NBPR.Artifact.HTTP do
  @moduledoc false

  @doc """
  Ensures `:inets` and `:ssl` are started so resolvers can use `:httpc`.

  `:inets.start/0` brings up the application *and* initialises the default
  httpc profile — `Application.ensure_all_started(:inets)` is not enough on
  OTP 28+, where `:httpc.request/4` needs the profile.
  """
  @spec start_apps!() :: :ok
  def start_apps! do
    case :inets.start() do
      :ok -> :ok
      {:error, {:already_started, :inets}} -> :ok
      {:error, reason} -> raise "failed to start :inets: #{inspect(reason)}"
    end

    case :ssl.start() do
      :ok -> :ok
      {:error, {:already_started, :ssl}} -> :ok
      {:error, reason} -> raise "failed to start :ssl: #{inspect(reason)}"
    end
  end
end
