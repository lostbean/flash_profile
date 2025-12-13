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

      # Package metadata
      package: package(),

      # Documentation
      name: "FlashProfile",
      description: "High-performance syntactic pattern discovery for string data using Zig NIFs",
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
        "Research Paper" => "https://doi.org/10.1145/3276520"
      },
      files:
        ~w(lib native mix.exs README.md LICENSE CHANGELOG.md .formatter.exs 12-2025-scalability-report.md PAPER_VALIDATION_REPORT.md)
    ]
  end

  defp docs do
    [
      main: "FlashProfile",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        {"LICENSE", [title: "License"]},
        "CHANGELOG.md",
        {"Architecture.md", [title: "Architecture"]},
        {"12-2025-scalability-report.md", [title: "Scalability Report"]},
        {"PAPER_VALIDATION_REPORT.md", [title: "Paper Validation"]}
      ],
      before_closing_head_tag: &before_closing_head_tag/1,
      groups_for_modules: [
        "Core API": [
          FlashProfile
        ],
        "Pattern System": [
          FlashProfile.Atom,
          FlashProfile.Pattern,
          FlashProfile.ProfileEntry
        ],
        Atoms: [
          FlashProfile.Atoms.CharClass,
          FlashProfile.Atoms.Constant,
          FlashProfile.Atoms.Defaults,
          FlashProfile.Atoms.Regex
        ],
        "NIF Backend": [
          FlashProfile.Native
        ]
      ],
      api_reference: true
    ]
  end

  # Mermaid support for ExDoc
  defp before_closing_head_tag(:html) do
    """
    <script src="https://cdn.jsdelivr.net/npm/mermaid@10.6.1/dist/mermaid.min.js"></script>
    <script>
      document.addEventListener("DOMContentLoaded", function () {
        mermaid.initialize({
          startOnLoad: false,
          theme: document.body.classList.contains("dark") ? "dark" : "default"
        });
        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp before_closing_head_tag(_), do: ""

  def cli do
    [
      preferred_envs: [
        precommit: :test,
        ci: :test
      ]
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
      {:zigler, "~> 0.15.1", runtime: false},
      {:stream_data, "~> 1.0", only: [:test, :dev]},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ]
  end
end
