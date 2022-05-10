defmodule ReqS3 do
  @moduledoc """
  `Req` plugin for [Amazon S3](https://aws.amazon.com/s3).

  ReqS3 handles a custom `s3://` url scheme that supports two endpoints:

  ```text
  s3://<bucket>        # list bucket items
  s3://<bucket>/<item> # get item content
  ```
  """

  @doc """
  Runs the plugin.

  ## Examples

      iex> req = Req.new() |> ReqS3.attach()
      iex> Req.get!(req, url: "s3://ossci-datasets").body
      [
        "mnist/",
        "mnist/t10k-images-idx3-ubyte.gz",
        "mnist/t10k-labels-idx1-ubyte.gz",
        "mnist/train-images-idx3-ubyte.gz",
        "mnist/train-labels-idx1-ubyte.gz"
      ]

      iex> req = Req.new() |> ReqS3.attach()
      iex> body = Req.get!(req, url: "s3://ossci-datasets/mnist/train-images-idx3-ubyte.gz").body
      iex> <<_::32, n_images::32, n_rows::32, n_cols::32, _body::binary>> = body
      iex> {n_images, n_rows, n_cols}
      {60_000, 28, 28}
  """
  def attach(request) do
    Req.Request.append_request_steps(request,
      req_s3_parse_url: &s3_parse_url/1
    )
  end

  defp s3_parse_url(request) do
    if request.url.scheme == "s3" do
      host = "#{request.url.host}.s3.amazonaws.com"
      url = %{request.url | scheme: "https", host: host, authority: host, port: 443}

      request
      |> Map.replace!(:url, url)
      |> Req.Request.append_response_steps(req_s3_decode_body: &decode_body/1)
    else
      request
    end
  end

  require Record

  for {name, fields} <- Record.extract_all(from_lib: "xmerl/include/xmerl.hrl") do
    Record.defrecordp(name, fields)
  end

  defp decode_body({request, response}) do
    if request.url.path in [nil, "/"] do
      opts = [space: :normalize, comments: false, encoding: :latin1]
      {doc, ''} = :xmerl_scan.string(String.to_charlist(response.body), opts)
      list = :xmerl_xpath.string('//ListBucketResult/Contents/Key/text()', doc)

      body =
        for xmlText(value: value) <- list do
          List.to_string(value)
        end

      {request, %{response | body: body}}
    else
      {request, response}
    end
  end
end
