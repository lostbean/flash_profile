defmodule FlashProfile.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/lostbean/flash_profile"

  def project do
    [
      app: :flash_profile,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      preferred_cli_env: [
        precommit: :test,
        ci: :test
      ],

      # Package metadata
      package: package(),

      # Documentation
      name: "FlashProfile",
      description:
        "Automatic regex pattern discovery for string columns using Microsoft's FlashProfile algorithm",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      name: "flash_profile",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Research Paper" =>
          "https://www.microsoft.com/en-us/research/publication/flashprofile-interactive-synthesis-of-syntactic-profiles/"
      },
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "FlashProfile",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        {"LICENSE", [title: "License"]}
      ],
      groups_for_modules: [
        "Core API": [
          FlashProfile
        ],
        "Pattern System": [
          FlashProfile.Pattern,
          FlashProfile.PatternSynthesizer,
          FlashProfile.CostModel
        ],
        "Text Analysis": [
          FlashProfile.Token,
          FlashProfile.Tokenizer,
          FlashProfile.Clustering
        ],
        Examples: [
          FlashProfile.Examples
        ]
      ],
      api_reference: true
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
