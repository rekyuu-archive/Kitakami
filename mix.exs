defmodule Kitakami.MixProject do
  use Mix.Project

  def project do
    [
      app: :kitakami,
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      applications: [:nadia],
      extra_applications: [:logger],
      mod: {Kitakami, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nadia, "~> 0.5.0"}
    ]
  end
end
