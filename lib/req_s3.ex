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
    |> Req.Request.register_options([:aws_endpoint_url_s3])
    |> add_request_steps_before([s3_handle_url: &__MODULE__.handle_s3_url/1], :put_aws_sigv4)
    |> Req.merge(options)
  end

  @doc """
  Handles the `s3://` URL scheme.

  This request step is automatically added on `ReqS3.attach(request)`.

  See module documentation for usage examples.

  ## Request Options

    * `:aws_endpoint_url_s3` - if set, the endpoint URL for S3-compatible services.
      If `AWS_ENDPOINT_URL_S3` system environment variable is set, it is considered first.
  """
  def handle_s3_url(request) do
    if request.url.scheme == "s3" do
      url = normalize_url(request.url, request.options[:aws_endpoint_url_s3])

      request
      |> Map.replace!(:url, url)
      |> Map.update!(:options, fn options ->
        access_key_id =
          options[:aws_sigv4][:access_key_id] || System.get_env("AWS_ACCESS_KEY_ID")

        secret_access_key =
          options[:aws_sigv4][:secret_access_key] || System.get_env("AWS_SECRET_ACCESS_KEY")

        if access_key_id do
          options = Map.put_new(options, :aws_sigv4, [])
          options = put_in(options[:aws_sigv4][:service], :s3)
          options = put_in(options[:aws_sigv4][:access_key_id], access_key_id)
          options = put_in(options[:aws_sigv4][:secret_access_key], secret_access_key)
          options
        else
          options
        end
      end)
      |> Req.Request.append_response_steps(req_s3_decode_body: &decode_body(&1, request.url.path))
    else
      request
    end
  end

  defp decode_body({request, response}, path) do
    if request.method in [:get, :head] and
         path in [nil, "", "/"] and
         request.options[:decode_body] != false and
         request.options[:raw] != true and
         match?(["application/xml" <> _], response.headers["content-type"]) do
      response = update_in(response.body, &ReqS3.XML.parse_s3/1)
      {request, response}
    else
      {request, response}
    end
  end

  @doc ~S"""
  Returns a presigned URL for fetching bucket object contents.

  ## Options

    * `:access_key_id` - the AWS access key id. Defaults to the value of `AWS_ACCESS_KEY_ID`
      system environment variable.

    * `:secret_access_key` - the AWS secret access key. Defaults to the value of
      `AWS_SECRET_ACCESS_KEY` system environment variable.

    * `:region` - the AWS region. Defaults to the value of `AWS_REGION` system environment
      variable, then `"us-east-1"`.

    * `:url` - the URL to presign, for example: `"https://{bucket}.s3.amazonaws.com/{key}"`,
      `s3://{bucket}/{key}`, etc. `s3://` URL uses `:endpoint_url` option described below.

      Instead of passing the `:url` option, you can instead pass `:bucket` and `:key` options
      which will generate `https://{bucket}.s3.amazonaws.com/{key}` (or
      `{endpoint_url}/{bucket}/{key}`).

    * `:endpoint_url` - if set, the endpoint URL for S3-compatible services. If
      `AWS_ENDPOINT_URL_S3` system environment variable is set, it is considered first.

  ## Examples

  Note: This example assumes `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variables
  are set.

      iex> req = Req.new() |> ReqS3.attach()
      iex> bucket = System.fetch_env!("BUCKET_NAME")
      iex> key = "key1"
      iex> %{status: 200} = Req.put!(req, url: "s3://#{bucket}/#{key}", body: "Hello, World!")
      iex> url = ReqS3.presign_url(bucket: bucket, key: key)
      iex> url =~ "https://#{bucket}.s3.amazonaws.com/#{key}?X-Amz-Algorithm=AWS4-HMAC-SHA256&"
      true
      iex> %{status: 200, body: body} = Req.get!(url)
      iex> body
      "Hello, World!"
  """
  def presign_url(options) do
    options
    |> Keyword.put_new_lazy(:access_key_id, fn ->
      System.get_env("AWS_ACCESS_KEY_ID") ||
        raise ArgumentError,
              ":access_key_id option or AWS_ACCESS_KEY_ID environment variable must be set"
    end)
    |> Keyword.put_new_lazy(:secret_access_key, fn ->
      System.get_env("AWS_SECRET_ACCESS_KEY") ||
        raise ArgumentError,
              ":secret_access_key option or AWS_SECRET_ACCESS_KEY environment variable must be set"
    end)
    |> Keyword.put_new(:region, System.get_env("AWS_REGION", "us-east-1"))
    |> Keyword.put_new(:method, :get)
    # TODO: deprecate :url in v0.3
    |> Keyword.put_new_lazy(:url, fn ->
      bucket = Keyword.fetch!(options, :bucket)
      key = Keyword.fetch!(options, :key)

      endpoint_url = options[:endpoint_url] || System.get_env("AWS_ENDPOINT_URL_S3")

      if endpoint_url do
        "#{endpoint_url}/#{bucket}/#{key}"
      else
        "https://#{bucket}.s3.amazonaws.com/#{key}"
      end
    end)
    |> Keyword.update!(:url, &normalize_url(&1, options[:endpoint_url]))
    |> Keyword.put(:service, "s3")
    |> Keyword.put(:datetime, DateTime.utc_now())
    |> Keyword.drop([:bucket, :key, :endpoint_url])
    |> Req.Utils.aws_sigv4_url()
    |> URI.to_string()
  end

  @doc """
  Returns presigned form for upload.

  ## Options

    * `:access_key_id` - the AWS access key id. Defaults to the value of `AWS_ACCESS_KEY_ID`
      system environment variable.

    * `:secret_access_key` - the AWS secret access key. Defaults to the value of
      `AWS_SECRET_ACCESS_KEY` system environment variable.

    * `:region` - if set, AWS region. Defaults to the value of `AWS_REGION` system environment
      variable, then `"us-east-1"`.

    * `:bucket` - the S3 bucket.

    * `:key` - the S3 bucket key.

    * `:endpoint_url` - if set, the endpoint URL for S3-compatible services. If
      `AWS_ENDPOINT_URL_S3` system environment variable is set, it is considered first.

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
      iex> form = ReqS3.presign_form(options)
      iex> form.url
      "https://bucket1.s3.amazonaws.com"
      iex> form.fields
      [
        {"key", "key1"},
        {"policy", "eyJjb25kaXRpb25z...ifQ=="},
        {"x-amz-algorithm", "AWS4-HMAC-SHA256"},
        {"x-amz-credential", "AKIA.../20240528/us-east-1/s3/aws4_request"},
        {"x-amz-date", "20240528T105226Z"},
        {"x-amz-server-side-encryption", "AES256"},
        {"x-amz-signature", "465315d202fbb2ce081f79fca755a958a18ff68d253e6d2a611ca4b2292d8925"}
      ]
  """
  def presign_form(options) when is_list(options) do
    # aws_credentials returns this key so let's ignore it
    options = Keyword.drop(options, [:credential_provider])

    Keyword.validate!(
      options,
      [
        :region,
        :access_key_id,
        :secret_access_key,
        :content_type,
        :max_size,
        :datetime,
        :expires_in,
        :bucket,
        :key,
        :endpoint_url
      ]
    )

    service = "s3"
    region = Keyword.get(options, :region, System.get_env("AWS_REGION", "us-east-1"))

    access_key_id =
      options[:access_key_id] || System.get_env("AWS_ACCESS_KEY_ID") ||
        raise ArgumentError,
              ":access_key_id option or AWS_ACCESS_KEY_ID system environment variable must be set"

    secret_access_key =
      options[:secret_access_key] || System.get_env("AWS_SECRET_ACCESS_KEY") ||
        raise ArgumentError,
              ":secret_access_key option or AWS_SECRET_ACCESS_KEY system environment variable must be set"

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

    endpoint_url = options[:endpoint_url] || System.get_env("AWS_ENDPOINT_URL_S3")

    url =
      if endpoint_url do
        "#{endpoint_url}/#{bucket}"
      else
        "https://#{options[:bucket]}.s3.amazonaws.com"
      end

    %{
      url: url,
      fields: Enum.to_list(fields)
    }
  end

  def presign_form(options) do
    presign_form(Enum.into(options, []))
  end

  defp normalize_url(string, endpoint_url) when is_binary(string) do
    normalize_url(URI.parse(string), endpoint_url)
  end

  defp normalize_url(%URI{scheme: "s3"} = url, endpoint_url) do
    url = %{url | scheme: "https", port: 443}
    endpoint_url = endpoint_url || System.get_env("AWS_ENDPOINT_URL_S3")

    case String.split(url.host, ".") do
      _ when url.host == "" ->
        url =
          if endpoint_url do
            endpoint_url = URI.new!(endpoint_url)

            %{
              url
              | scheme: endpoint_url.scheme,
                host: endpoint_url.host,
                authority: nil,
                port: endpoint_url.port
            }
          else
            host = "s3.amazonaws.com"
            %{url | host: host, authority: nil, path: "/"}
          end

        url

      [bucket] ->
        url =
          if endpoint_url do
            endpoint_url = URI.new!(endpoint_url)

            %{
              url
              | scheme: endpoint_url.scheme,
                host: endpoint_url.host,
                authority: nil,
                port: endpoint_url.port,
                path: "/#{bucket}#{url.path}"
            }
          else
            host = "#{bucket}.s3.amazonaws.com"
            %{url | host: host, authority: nil}
          end

        url

      [_ | _]  ->
        # bucket has dots in it
        bucket = url.host

        url =
          if endpoint_url do
            endpoint_url = URI.new!(endpoint_url)

            %{
              url
              | scheme: endpoint_url.scheme,
                host: endpoint_url.host,
                authority: nil,
                port: endpoint_url.port,
                path: "/#{bucket}#{url.path}"
            }
          else
            host = "s3.amazonaws.com"
            %{url | host: host, authority: nil, path: "/#{bucket}#{url.path}"}
          end

        url

      # leave e.g. s3.amazonaws.com as is
      _ ->
        url
    end
  end

  defp normalize_url(%URI{} = url, _endpoint_url) do
    url
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
