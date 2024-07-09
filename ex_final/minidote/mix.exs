defmodule Minidote.MixProject do
  use Mix.Project

  def project do
    [
      app: :minidote,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: [
        test: "test --no-start" # don't start the minidote application on testing
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Minidote.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:antidote_crdt, "~> 0.1.3"},
      {:meck, "~> 0.9.2"},
      {:dialyxir, "~> 1.4.3", only: [:dev, :test], runtime: false},
      {:gradient, github: "esl/gradient", only: [:dev], runtime: false}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
