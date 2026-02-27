defmodule Spector.MixProject do
  use Mix.Project

  @version "0.7.0"
  @source_url "https://github.com/ityonemo/spector"

  def project do
    [
      app: :spector,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Spector",
      description: "CQRS-style event sourcing for Ecto schemas",
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/_support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:ecto, "~> 3.12"},
      {:ecto_sql, "~> 3.12"},
      {:uuidv7, "~> 1.0"},
      {:telemetry, "~> 1.0"},
      {:postgrex, "~> 0.19", only: :test},
      {:stream_data, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib guides .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "Spector",
      extras: ["README.md", "guides/AI_chat.md", "guides/basic_chat.md", "guides/links.md"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ]
    ]
  end
end
