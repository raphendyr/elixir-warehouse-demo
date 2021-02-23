defmodule Warehouse.MixProject do
  use Mix.Project

  def project do
    [
      app: :warehouse,
      version: "0.1.0",
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Warehouse.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # Phoenix
      {:phoenix, "~> 1.5.4"},
      {:phoenix_html, "~> 2.11"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_dashboard, "~> 0.2"},
      {:telemetry_metrics, "~> 0.4"},
      {:telemetry_poller, "~> 0.4"},
      {:gettext, "~> 0.11"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      # Ecto
      {:phoenix_ecto, "~> 4.1"},
      {:ecto_sql, "~> 3.4"},
      # Tesla
      {:tesla, "~> 1.3.0"},
      #  Tesla,Middleware.JSON
      #{:jason, ">= 1.0.0"},
      #  Tesla.Adapter.Hackney
      #{:hackney, "~> 1.15.2"},
      #  Tesla.Adapter.Gun
      #{:gun, "~> 1.3"},
      {:gun, override: true, github: "ninenines/gun"},
      {:cowlib, override: true, git: "https://github.com/ninenines/cowlib", ref: "2.9.0"},
      {:idna, "~> 6.0"},
      {:castore, "~> 0.1"},
      # ProductCache.ApiClient
      {:erlsom, "~> 1.5"},
      # Debug
      #{:rexbug, ">= 1.0.0"},
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "cmd npm install --prefix assets"]
    ]
  end
end
