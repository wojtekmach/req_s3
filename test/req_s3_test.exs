defmodule ReqS3Test do
  use ExUnit.Case, async: true

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

  describe "attach/1" do
    test "inserts s3_handle_url request step before put_aws_sigv4" do
      req = Req.new() |> ReqS3.attach()

      step_names = Keyword.keys(req.request_steps)
      assert :s3_handle_url in step_names

      assert Enum.find_index(step_names, &(&1 == :s3_handle_url)) <
               Enum.find_index(step_names, &(&1 == :put_aws_sigv4))
    end

    test "converts s3:// URLs when running the request" do
      req =
        Req.new(
          "s3://my-bucket/path/to/object.json",
          plugins: [ReqS3],
          plug: fn conn ->
            assert Plug.Conn.request_url(conn) ==
                     "https://my-bucket.s3.amazonaws.com/path/to/object.json"

            Plug.Conn.send_resp(conn, 200, "")
          end
        )

      resp = Req.request!(req)
      assert resp.status == 200
    end
  end

  @tag :integration
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
    put_env("AWS_ENDPOINT_URL_S3", "https://s3.amazonaws.com")

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
    put_env("AWS_ENDPOINT_URL_S3", @endpoint_url_s3)
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
    test "set from system env" do
      put_env("AWS_ACCESS_KEY_ID", "key-from-env")
      put_env("AWS_SECRET_ACCESS_KEY", "secret-from-env")

      req =
        Req.new(
          "s3://",
          plugins: [ReqS3],
          plug: fn conn ->
            assert ["AWS4-HMAC-SHA256 Credential=key-from-env/" <> _] =
                     Plug.Conn.get_req_header(conn, "authorization")

            Plug.Conn.send_resp(conn, 200, "")
          end
        )

      resp = Req.request!(req)
      assert resp.status == 200
    after
      put_env("AWS_ACCESS_KEY_ID", @access_key_id)
      put_env("AWS_SECRET_ACCESS_KEY", @secret_access_key)
    end

    test "can be overridden" do
      put_env("AWS_ACCESS_KEY_ID", "key-from-env")
      put_env("AWS_SECRET_ACCESS_KEY", "secret-from-env")

      req =
        Req.new(
          "s3://",
          plugins: [ReqS3],
          aws_sigv4: [access_key_id: "foo"],
          plug: fn conn ->
            assert ["AWS4-HMAC-SHA256 Credential=foo/" <> _] =
                     Plug.Conn.get_req_header(conn, "authorization")

            Plug.Conn.send_resp(conn, 200, "")
          end
        )

      resp = Req.request!(req)
      assert resp.status == 200
    after
      put_env("AWS_ACCESS_KEY_ID", @access_key_id)
      put_env("AWS_SECRET_ACCESS_KEY", @secret_access_key)
    end

    test "is not set when option nor env is not set " do
      System.delete_env("AWS_ACCESS_KEY_ID")

      req =
        Req.new(
          "s3://",
          plugins: [ReqS3],
          plug: fn conn ->
            assert Plug.Conn.get_req_header(conn, "authorization") == []
            Plug.Conn.send_resp(conn, 200, "")
          end
        )

      resp = Req.request!(req)
      assert resp.status == 200
    after
      put_env("AWS_ACCESS_KEY_ID", @access_key_id)
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

  @tag :integration
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
    put_env("AWS_ENDPOINT_URL_S3", "https://custom")

    assert "https://custom/bucket/key?X-Amz-Algorithm=AWS4-HMAC-SHA256&" <> _ =
             ReqS3.presign_url(
               url: "s3://bucket/key",
               access_key_id: "",
               secret_access_key: ""
             )
  after
    put_env("AWS_ENDPOINT_URL_S3", @endpoint_url_s3)
  end

  @tag :integration
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

  def put_env(name, value) when is_binary(value) do
    System.put_env(name, value)
  end

  def put_env(name, nil) do
    System.delete_env(name)
  end
end
