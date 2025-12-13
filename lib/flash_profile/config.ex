defmodule FlashProfile.Config do
  @moduledoc """
  Configuration for FlashProfile backend selection.

  Allows switching between Zig NIF and pure Elixir implementations
  for benchmarking and comparison purposes.

  ## Configuration

  Set the backend via application config or environment variable:

      # config/config.exs
      config :flash_profile, :backend, :zig  # or :elixir

      # Environment variable
      FLASH_PROFILE_BACKEND=elixir mix run scripts/benchmark.exs

  ## Backends

  - `:zig` (default) - Uses Zig NIFs for performance-critical operations
  - `:elixir` - Uses pure Elixir implementation for all operations
  """

  @doc """
  Get the current backend (:zig or :elixir).
  Defaults to :zig if not configured.
  """
  @spec backend() :: :zig | :elixir
  def backend do
    case System.get_env("FLASH_PROFILE_BACKEND") do
      "elixir" -> :elixir
      "zig" -> :zig
      nil -> Application.get_env(:flash_profile, :backend, :zig)
      _ -> :zig
    end
  end

  @doc """
  Check if Zig backend is enabled.
  """
  @spec use_zig?() :: boolean()
  def use_zig?, do: backend() == :zig

  @doc """
  Check if pure Elixir backend is enabled.
  """
  @spec use_elixir?() :: boolean()
  def use_elixir?, do: backend() == :elixir
end
