defmodule ReqS3Test do
  use ExUnit.Case, async: true

  @moduletag :integration
  doctest ReqS3, tags: [:integration], only: [presign_url: 1]

  if System.get_env("REQ_AWS_ACCESS_KEY_ID") do
    for name <- ~w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3],
        value = System.get_env("REQ_#{name}") do
      System.put_env(name, value)
    end
  end

  @access_key_id System.get_env("REQ_AWS_ACCESS_KEY_ID")
  @secret_access_key System.get_env("REQ_AWS_SECRET_ACCESS_KEY")
  @endpoint_url_s3 System.get_env("REQ_AWS_ENDPOINT_URL_S3")

  setup_all do
    if @access_key_id do
      %{status: 200} =
        Req.put!(
          plugins: [ReqS3],
          url: "s3://#{System.fetch_env!("BUCKET_NAME")}/key1",
          body: "Hello, World!"
        )
    end

    :ok
  end

  test "list buckets" do
    req =
      Req.new()
      |> ReqS3.attach()

    bucket = System.fetch_env!("BUCKET_NAME")
    resp = Req.get!(req, url: "s3://")
    %{"ListAllMyBucketsResult" => %{"Buckets" => buckets}} = resp.body
    assert Enum.any?(buckets, fn %{"Name" => name} -> name == bucket end)
  end

  @tag :integration
  test "list objects" do
    req =
      Req.new()
      |> ReqS3.attach()

    body = Req.get!(req, url: "s3://ossci-datasets").body

    assert %{
             "ListBucketResult" => %{
               "Name" => "ossci-datasets",
               "Contents" => [
                 %{"Key" => "mnist/", "Size" => "0"},
                 %{"Key" => "mnist/t10k-images-idx3-ubyte.gz", "Size" => "1648877"}
                 | _
               ]
             }
           } = body
  end

  @tag :integration
  test "list objects with bucket with period in name" do
    req =
      Req.new()
      |> ReqS3.attach()

    %{status: 200} = Req.put!(req, url: "s3://wojtekmach.test")
    %{status: 200} = Req.put!(req, url: "s3://wojtekmach.test/1", body: "1")
    %{status: 200, body: "1"} = Req.get!(req, url: "s3://wojtekmach.test/1")
  end

  @tag :integration
  test "list objects with custom AWS_ENDPOINT_URL_S3" do
    System.put_env("AWS_ENDPOINT_URL_S3", "https://s3.amazonaws.com")

    req =
      Req.new()
      |> ReqS3.attach()

    body = Req.get!(req, url: "s3://ossci-datasets").body

    assert %{
             "ListBucketResult" => %{
               "Name" => "ossci-datasets",
               "Contents" => [
                 %{"Key" => "mnist/", "Size" => "0"},
                 %{"Key" => "mnist/t10k-images-idx3-ubyte.gz", "Size" => "1648877"}
                 | _
               ]
             }
           } = body
  after
    if @endpoint_url_s3 do
      System.put_env("AWS_ENDPOINT_URL_S3", @endpoint_url_s3)
    else
      System.delete_env("AWS_ENDPOINT_URL_S3")
    end
  end

  @tag :integration
  test "list versions" do
    bucket = System.fetch_env!("BUCKET_NAME")

    req =
      Req.new()
      |> ReqS3.attach()

    body = Req.get!(req, url: "s3://#{bucket}?versions").body

    assert %{
             "ListVersionsResult" => %{
               "Name" => ^bucket,
               "Version" => [%{"Key" => _, "VersionId" => _} | _]
             }
           } = body
  end

  describe "aws_sigv4" do
    @describetag :integration

    test "set from system env" do
      req = Req.new(plugins: [ReqS3], url: "s3://")

      assert Map.new(Req.Request.prepare(req).options.aws_sigv4) == %{
               service: :s3,
               access_key_id: @access_key_id,
               secret_access_key: @secret_access_key
             }
    end

    test "can be overridden" do
      req = Req.new(plugins: [ReqS3], url: "s3://", aws_sigv4: [access_key_id: "foo"])

      assert Map.new(Req.Request.prepare(req).options.aws_sigv4) == %{
               service: :s3,
               access_key_id: "foo",
               secret_access_key: @secret_access_key
             }
    end

    test "is not set when option nor env is not set " do
      System.delete_env("AWS_ACCESS_KEY_ID")

      req = Req.new(plugins: [ReqS3], url: "s3://")
      assert Req.Request.prepare(req).options[:aws_sigv4] == nil
    after
      System.put_env("AWS_ACCESS_KEY_ID", @access_key_id)
    end
  end

  test "presign_url/1" do
    options = [
      url: "s3://wojtekmach-test/foo",
      access_key_id: "foo",
      secret_access_key: "bar"
    ]

    assert "https://wojtekmach-test.s3.amazonaws.com/foo?X-Amz-Algorithm=AWS4-HMAC-SHA256&" <> _ =
             ReqS3.presign_url(options)
  end

  test "presign_url/1 encode path" do
    options = [
      url: "s3://wojtekmach-test/hello world.txt",
      access_key_id: "foo",
      secret_access_key: "bar"
    ]

    assert "https://wojtekmach-test.s3.amazonaws.com/hello%20world.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&" <>
             _ = ReqS3.presign_url(options)
  end

  test "presign_url/1 upload" do
    url = ReqS3.presign_url(url: "s3://wojtekmach-test/foo", method: :put)
    body = "hi#{Time.utc_now()}"

    %{status: 200} =
      Req.put!(url, body: body)

    %{status: 200, body: ^body} =
      Req.get!("https://wojtekmach-test.s3.amazonaws.com/foo",
        aws_sigv4: [
          service: :s3,
          access_key_id: @access_key_id,
          secret_access_key: @secret_access_key
        ]
      )
  end

  test "presign_url/1 custom endpoint url" do
    assert "https://custom/bucket/key?X-Amz-Algorithm=AWS4-HMAC-SHA256&" <> _ =
             ReqS3.presign_url(
               url: "s3://bucket/key",
               endpoint_url: "https://custom",
               access_key_id: "",
               secret_access_key: ""
             )
  end

  test "presign_url/1 custom endpoint url from env" do
    System.put_env("AWS_ENDPOINT_URL_S3", "https://custom")

    assert "https://custom/bucket/key?X-Amz-Algorithm=AWS4-HMAC-SHA256&" <> _ =
             ReqS3.presign_url(
               url: "s3://bucket/key",
               access_key_id: "",
               secret_access_key: ""
             )
  after
    if @endpoint_url_s3 do
      System.put_env("AWS_ENDPOINT_URL_S3", @endpoint_url_s3)
    else
      System.delete_env("AWS_ENDPOINT_URL_S3")
    end
  end

  @tag :tmp_dir
  test "presign_form/1", %{tmp_dir: tmp_dir} do
    bucket = System.fetch_env!("BUCKET_NAME")

    options = [
      bucket: bucket,
      key: "key1",
      content_type: "text/plain"
    ]

    form = ReqS3.presign_form(options)
    body = "test#{DateTime.utc_now()}"

    File.write!("#{tmp_dir}/foo.txt", body)
    file = File.stream!("#{tmp_dir}/foo.txt")

    %{status: 204} =
      Req.post!(
        url: form.url,
        form_multipart: form.fields ++ [file: file]
      )

    %{status: 200, body: ^body, headers: %{"content-type" => ["text/plain"]}} =
      Req.get!(
        "#{form.url}/key1",
        aws_sigv4: [
          service: :s3,
          access_key_id: @access_key_id,
          secret_access_key: @secret_access_key
        ]
      )
  end
end
