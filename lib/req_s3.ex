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
      iex> Req.get!(req, url: "s3://ossci-datasets").body |> Enum.take(5)
      [
        "mnist/",
        "mnist/t10k-images-idx3-ubyte.gz",
        "mnist/t10k-labels-idx1-ubyte.gz",
        "mnist/train-images-idx3-ubyte.gz",
        "mnist/train-labels-idx1-ubyte.gz"
      ]

      iex> req = Req.new() |> ReqS3.attach()
      iex> body = Req.get!(req, url: "s3://ossci-datasets/mnist/t10k-images-idx3-ubyte.gz").body
      iex> <<_::32, n_images::32, n_rows::32, n_cols::32, _body::binary>> = body
      iex> {n_images, n_rows, n_cols}
      {10_000, 28, 28}
  """
  def attach(request) do
    request = update_in(request.request_steps, &attach_step/1)
    request = update_in(request.current_request_steps, &attach_current_step/1)
    request
  end

  defp attach_step([{:put_aws_sigv4, _} = put_aws_sigv4_step | rest]) do
    [{:s3_parse_url, &parse_url/1}, put_aws_sigv4_step | rest]
  end

  defp attach_step([step | rest]) do
    [step | attach_step(rest)]
  end

  defp attach_step([]) do
    []
  end

  defp attach_current_step([:put_aws_sigv4 | rest]) do
    [:s3_parse_url, :put_aws_sigv4 | rest]
  end

  defp attach_current_step([step | rest]) do
    [step | attach_current_step(rest)]
  end

  defp attach_current_step([]) do
    []
  end

  def new(options \\ []) when is_list(options) do
    Req.new()
    |> attach()
    |> Req.merge(options)
  end

  defp parse_url(request) do
    if request.url.scheme == "s3" do
      request
      |> Map.update!(:url, &normalize_url/1)
      |> Req.Request.append_response_steps(req_s3_decode_body: &decode_body/1)
    else
      request
    end
  end

  defp decode_body({request, response}) do
    if request.url.path in [nil, "/"] do
      response = update_in(response.body, &ReqS3.XML.parse_s3_list_objects/1)
      {request, response}
    else
      {request, response}
    end
  end

  @doc """
  Returns a presigned URL for fetching bucket object contents.

  ## Options

    * `:access_key_id` - the AWS access key id.

    * `:secret_access_key` - the AWS secret access key.

    * `:region` - if set, AWS region. Defaults to `"us-east-1"`.

  ## Examples

      iex> options = [
      ...>   access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
      ...>   secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY")
      ...> ]
      iex> url = ReqS3.presign_url("s3://wojtekmach-test/key1", options)
      iex> String.starts_with?(url, "https://wojtekmach-test.s3.amazonaws.com/key1?X-Amz-Algorithm=AWS4-HMAC-SHA256&")
      true
      iex> %{status: 200, body: body} = Req.get!(url)
      iex> body
      "Hello, World!"
  """
  def presign_url(url, options \\ [])
      when (is_binary(url) or is_struct(url, URI)) and is_list(options) do
    Keyword.fetch!(options, :access_key_id)
    Keyword.fetch!(options, :secret_access_key)
    url = url |> URI.new!() |> normalize_url()

    options =
      options
      |> Keyword.put(:method, :get)
      |> Keyword.put(:url, url)
      |> Keyword.put_new(:region, "us-east-1")
      |> Keyword.put(:service, "s3")
      |> Keyword.put(:datetime, DateTime.utc_now())

    options |> Req.Utils.aws_sigv4_url() |> URI.to_string()
  end

  defp normalize_url(%URI{scheme: "s3"} = url) do
    host =
      case String.split(url.host, ".") do
        [host] ->
          "#{host}.s3.amazonaws.com"

        _ ->
          # leave e.g. s3.amazonaws.com as is
          url.host
      end

    %{url | scheme: "https", host: host, authority: host, port: 443}
  end

  defp normalize_url(url) do
    url
  end
end
