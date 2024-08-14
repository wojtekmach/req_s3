defmodule ReqS3.MixProject do
  use Mix.Project

  def project do
    [
      app: :req_s3,
      version: "0.2.2",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: [
        "test.all": ["test --include integration"]
      ],
      preferred_cli_env: [
        "test.all": :test,
        docs: :docs,
        "hex.publish": :docs
      ],
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md"]
      ],
      package: [
        description: "Req plugin for S3.",
        licenses: ["Apache-2.0"],
        links: %{
          "GitHub" => "https://github.com/wojtekmach/req_s3",
          "Changelog" => "https://hexdocs.pm/req_s3/changelog.html"
        }
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :xmerl]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5.6"},
      {:ex_doc, ">= 0.0.0", only: :docs}
    ]
  end
end
