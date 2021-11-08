defmodule ReqS3.MixProject do
  use Mix.Project

  def project do
    [
      app: :req_s3,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :xmerl]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.2.0"}
    ]
  end
end
