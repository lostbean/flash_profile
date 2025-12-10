defmodule FlashProfile.MixProject do
  use Mix.Project

  def project do
    [
      app: :flash_profile,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      preferred_cli_env: [
        precommit: :test,
        ci: :test
      ],
      name: "FlashProfile",
      description: "Automatic regex pattern discovery for string columns",
      source_url: "https://github.com/lostbean/flash_profile",
      docs: [
        main: "FlashProfile",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp aliases do
    [
      precommit: [
        "format",
        "compile --warnings-as-errors",
        "test"
      ],
      ci: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test"
      ]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
