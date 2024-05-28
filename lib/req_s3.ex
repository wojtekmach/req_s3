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

  @doc """
  Returns presigned form values for upload.

  ## Options

    * `:access_key_id`

    * `:secret_access_key`

    * `:region`

    * `:bucket`

    * `:key`

    * `:content_type`

    * `:max_size`

    * `:datetime`

    * `:expires_in`

  ## Examples

  iex> options = [
  ...>   access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
  ...>   secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY"),
  ...>   bucket: "wojtekmach-test",
  ...>   key: "key1",
  ...>   expires_in: :timer.hours(1)
  ...> ]
  iex> ReqS3.presign_form(options)
  %{
    "key" => "key1",
    "policy" => "eyJjb25kaXRpb25z...ifQ==",
    "x-amz-algorithm" => "AWS4-HMAC-SHA256",
    "x-amz-credential" => "AKIA.../20240528/us-east-1/s3/aws4_request",
    "x-amz-date" => "20240528T105226Z",
    "x-amz-server-side-encryption" => "AES256",
    "x-amz-signature" => "465315d202fbb2ce081f79fca755a958a18ff68d253e6d2a611ca4b2292d8925"
  }
  """
  def presign_form(options) when is_list(options) do
    service = "s3"
    region = Keyword.get(options, :region, "us-east-1")
    access_key_id = Keyword.fetch!(options, :access_key_id)
    secret_access_key = Keyword.fetch!(options, :secret_access_key)
    bucket = Keyword.fetch!(options, :bucket)
    key = Keyword.fetch!(options, :key)
    content_type = Keyword.get(options, :content_type)
    max_size = Keyword.get(options, :max_size)
    datetime = Keyword.get(options, :datetime, DateTime.utc_now())
    expires_in = Keyword.get(options, :expires_in, 24 * 60 * 60 * 1000)

    datetime = DateTime.truncate(datetime, :second)
    datetime = DateTime.add(datetime, expires_in, :millisecond)
    datetime_string = datetime |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)
    date_string = binary_part(datetime_string, 0, 8)

    credential = "#{access_key_id}/#{date_string}/#{region}/#{service}/aws4_request"

    amz_headers = [
      {"x-amz-server-side-encryption", "AES256"},
      {"x-amz-credential", credential},
      {"x-amz-algorithm", "AWS4-HMAC-SHA256"},
      {"x-amz-date", datetime_string}
    ]

    policy = %{
      "expiration" => DateTime.to_iso8601(datetime),
      "conditions" =>
        [
          %{"bucket" => "#{bucket}"},
          ["eq", "$key", "#{key}"],
          # TODO: don't include content-type if it's empty. Same for max size
          ["eq", "$Content-Type", "#{content_type}"],
          ["content-length-range", 0, max_size]
        ] ++ Enum.map(amz_headers, fn {key, value} -> %{key => value} end)
    }

    encoded_policy = policy |> Jason.encode!() |> Base.encode64()

    signature =
      Req.Utils.aws_sigv4(
        encoded_policy,
        date_string,
        region,
        service,
        secret_access_key
      )

    Map.merge(
      Map.new(amz_headers),
      %{
        "key" => key,
        "content-type" => content_type,
        "policy" => encoded_policy,
        "x-amz-signature" => signature
      }
    )
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
