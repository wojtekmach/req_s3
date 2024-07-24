defmodule ReqS3 do
  @external_resource "README.md"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  @doc """
  Attaches the plugin.
  """
  def attach(request, options \\ []) do
    request
    |> add_request_steps_before([s3_handle_url: &handle_s3_url/1], :put_aws_sigv4)
    |> Req.merge(options)
  end

  defp handle_s3_url(request) do
    if request.url.scheme == "s3" do
      {url, bucket} = parse_url(request.url)

      request
      |> Map.replace!(:url, url)
      |> Map.update!(:options, fn options ->
        if options[:aws_sigv4] do
          put_in(options[:aws_sigv4][:service], :s3)
        else
          options
        end
      end)
      |> Req.Request.append_response_steps(
        req_s3_decode_body: &decode_body(&1, bucket, request.url.path)
      )
    else
      request
    end
  end

  defp decode_body({request, response}, bucket, path) do
    if request.method in [:get, :head] and
         path in [nil, ""] and
         request.options[:decode_body] != false and
         request.options[:raw] != true and
         match?(["application/xml" <> _], response.headers["content-type"]) do
      fun =
        if bucket do
          &ReqS3.XML.parse_s3_list_objects/1
        else
          &ReqS3.XML.parse_s3_list_buckets/1
        end

      response = update_in(response.body, fun)
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

    * `:url` - the URL to presign, for example: `"https://bucket.s3.amazonaws.com"` or `s3://bucket`.

       Instead of passing the `:url` option, you can also pass `:bucket` and `:key` options
       which will generate a `https://{bucket}.s3.amazonaws.com/{key}` url.

  ## Examples

      iex> options = [
      ...>   access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
      ...>   secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY"),
      ...> ]
      iex> req = Req.new() |> ReqS3.attach(aws_sigv4: options)
      iex> %{status: 200} = Req.put!(req, url: "s3://wojtekmach-test/key1", body: "Hello, World!")
      iex> url = ReqS3.presign_url([url: "s3://wojtekmach-test/key1"] ++ options)
      iex> "https://wojtekmach-test.s3.amazonaws.com/key1?X-Amz-Algorithm=AWS4-HMAC" <> _ = url
      iex> %{status: 200, body: body} = Req.get!(url)
      iex> body
      "Hello, World!"
  """
  def presign_url(options) do
    options
    |> Keyword.put_new(:method, :get)
    |> Keyword.put_new_lazy(:url, fn ->
      bucket = Keyword.fetch!(options, :bucket)
      key = Keyword.fetch!(options, :key)
      "https://#{bucket}.s3.amazonaws.com/#{key}"
    end)
    |> Keyword.update!(:url, &normalize_url/1)
    |> Keyword.put_new(:region, "us-east-1")
    |> Keyword.put(:service, "s3")
    |> Keyword.put(:datetime, DateTime.utc_now())
    |> Keyword.drop([:bucket, :key])
    |> Req.Utils.aws_sigv4_url()
    |> URI.to_string()
  end

  @doc """
  Returns presigned form for upload.

  ## Options

    * `:access_key_id` - the access key id.

    * `:secret_access_key` - the secret access key.

    * `:region` - the S3 region, defaults to `"us-east-1"`.

    * `:bucket` - the S3 bucket.

    * `:key` - the S3 bucket key.

    * `:content_type` - if set, the content-type of the uploaded object.

    * `:max_size` - if set, the maximum size of the uploaded object.

    * `:expires_in` - the time in milliseconds before the signed upload expires. Defaults to 1h
      (`60 * 60 * 1000` milliseconds).

    * `:datetime` - the request datetime, defaults to `DateTime.utc_now(:second)`.

  ## Examples

      iex> options = [
      ...>   access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
      ...>   secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY"),
      ...>   bucket: "bucket1",
      ...>   key: "key1",
      ...>   expires_in: :timer.hours(1)
      ...> ]
      iex> %{url: url, fields: fields} = ReqS3.presign_form(options)
      iex> url
      "https://bucket1.s3.amazonaws.com"
      iex> fields
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
    # aws_credentials returns this key so let's ignore it
    options = Keyword.drop(options, [:credential_provider])

    service = "s3"
    region = Keyword.get(options, :region, "us-east-1")
    access_key_id = Keyword.fetch!(options, :access_key_id)
    secret_access_key = Keyword.fetch!(options, :secret_access_key)

    bucket = Keyword.fetch!(options, :bucket)
    key = Keyword.fetch!(options, :key)
    content_type = Keyword.get(options, :content_type)
    max_size = Keyword.get(options, :max_size)
    datetime = Keyword.get(options, :datetime, DateTime.utc_now())
    expires_in = Keyword.get(options, :expires_in, 60 * 60 * 1000)

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

    content_type_conditions =
      if content_type do
        [["eq", "$Content-Type", "#{content_type}"]]
      else
        []
      end

    content_length_range_conditions =
      if max_size do
        [["content-length-range", 0, max_size]]
      else
        []
      end

    conditions =
      [
        %{"bucket" => "#{bucket}"},
        ["eq", "$key", "#{key}"]
      ] ++
        content_type_conditions ++
        content_length_range_conditions ++
        Enum.map(amz_headers, fn {key, value} -> %{key => value} end)

    policy = %{
      "expiration" => DateTime.to_iso8601(datetime),
      "conditions" => conditions
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

    fields =
      Map.merge(
        Map.new(amz_headers),
        %{
          "key" => key,
          "policy" => encoded_policy,
          "x-amz-signature" => signature
        }
      )

    fields =
      if content_type do
        Map.merge(fields, %{"content-type" => content_type})
      else
        fields
      end

    %{
      url: "https://#{options[:bucket]}.s3.amazonaws.com",
      fields: Enum.to_list(fields)
    }
  end

  def presign_form(options) do
    presign_form(Enum.into(options, []))
  end

  defp normalize_url(string) when is_binary(string) do
    normalize_url(URI.new!(string))
  end

  defp normalize_url(%URI{scheme: "s3"} = url) do
    {url, _bucket} = parse_url(url)
    url
  end

  defp normalize_url(%URI{} = url) do
    url
  end

  defp parse_url(url) do
    url = %{url | scheme: "https", port: 443}

    case String.split(url.host, ".") do
      _ when url.host == "" ->
        url =
          if endpoint_url = System.get_env("AWS_ENDPOINT_URL_S3") do
            host = URI.new!(endpoint_url).host
            %{url | host: host, authority: nil}
          else
            host = "s3.amazonaws.com"
            %{url | host: host, authority: nil, path: "/"}
          end

        {url, nil}

      [bucket] ->
        url =
          if endpoint_url = System.get_env("AWS_ENDPOINT_URL_S3") do
            host = URI.new!(endpoint_url).host
            %{url | host: host, authority: nil, path: "/#{bucket}#{url.path}"}
          else
            host = "#{bucket}.s3.amazonaws.com"
            %{url | host: host, authority: nil}
          end

        {url, bucket}

      # leave e.g. s3.amazonaws.com as is
      _ ->
        {url, nil}
    end
  end

  # TODO: Req.add_request_steps(req, steps, before: step)
  defp add_request_steps_before(request, steps, before_step_name) do
    request
    |> Map.update!(:request_steps, &prepend_steps(&1, steps, before_step_name))
    |> Map.update!(:current_request_steps, &prepend_current_steps(&1, steps, before_step_name))
  end

  defp prepend_steps([{before_step_name, _} | _] = rest, steps, before_step_name) do
    steps ++ rest
  end

  defp prepend_steps([step | rest], steps, before_step_name) do
    [step | prepend_steps(rest, steps, before_step_name)]
  end

  defp prepend_steps([], _steps, _before_step_name) do
    []
  end

  defp prepend_current_steps([before_step_name | _] = rest, steps, before_step_name) do
    Keyword.keys(steps) ++ rest
  end

  defp prepend_current_steps([step | rest], steps, before_step_name) do
    [step | prepend_current_steps(rest, steps, before_step_name)]
  end

  defp prepend_current_steps([], _steps, _before_step_name) do
    []
  end
end
