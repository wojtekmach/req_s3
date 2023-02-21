defmodule ReqS3 do
  @moduledoc """
  `Req` plugin for [Amazon S3](https://aws.amazon.com/s3).

  ReqS3 handles a custom `s3://` url scheme that supports these endpoints:

  ```text
  GET s3://<bucket>        # list bucket items
  GET s3://<bucket>/<item> # get item content
  PUT s3://<bucket>/<item> # put item content
  ```
  """

  @doc """
  Runs the plugin.

  ## Request Options

    * `:aws_sigv4` - A list of options for AWS signature:

        * `:access_key_id` - The AWS Access Key ID.

        * `:secret_access_key` - The AWS Secret Access Key.

        * `:region` - The AWS region, defaults to `"us-east-1"`.

        * `:options` - Additional AWS signature options, see: `:aws_signature.sign_v4/10` for more information.

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
  def attach(request, options \\ []) do
    request
    |> Req.Request.append_request_steps(
      req_s3_parse_url: &parse_url/1,
      req_s3_put_sigv4: &put_sigv4/1
    )
    |> Req.Request.register_options([:aws_sigv4])
    |> Req.Request.merge_options(options)
  end

  defp parse_url(request) do
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

  defp put_sigv4(request) do
    if aws_options = request.options[:aws_sigv4] do
      access_key_id = Keyword.fetch!(aws_options, :access_key_id)
      secret_access_key = Keyword.fetch!(aws_options, :secret_access_key)
      region = Keyword.get(aws_options, :region, "us-east-1")
      options = Keyword.get(aws_options, :options, [])

      headers =
        :aws_signature.sign_v4(
          access_key_id,
          secret_access_key,
          region,
          "s3",
          :calendar.universal_time(),
          to_string(request.method),
          to_string(request.url),
          [{"host", request.url.host}] ++ request.headers,
          request.body,
          options
        )

      %{request | headers: headers}
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
      {doc, ~c""} = :xmerl_scan.string(String.to_charlist(response.body), opts)
      list = :xmerl_xpath.string(~c"//ListBucketResult/Contents/Key/text()", doc)

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
