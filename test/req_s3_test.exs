defmodule ReqS3Test do
  use ExUnit.Case, async: true

  @moduletag :integration
  doctest ReqS3, tags: [:integration], only: [presign_url: 1]

  setup_all do
    if System.get_env("REQ_AWS_ACCESS_KEY_ID") do
      for name <- ~w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY] do
        System.put_env(name, System.fetch_env!("REQ_#{name}"))
      end

      options = [
        service: "s3",
        access_key_id: System.fetch_env!("REQ_AWS_ACCESS_KEY_ID"),
        secret_access_key: System.fetch_env!("REQ_AWS_SECRET_ACCESS_KEY")
      ]

      %{status: 200} =
        Req.put!(
          plugins: [ReqS3],
          url: "s3://wojtekmach-test/key1",
          aws_sigv4: options,
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

  test "list objects with custom AWS_ENDPOINT_URL_S3" do
    old = System.get_env("AWS_ENDPOINT_URL_S3")

    try do
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
      if old do
        System.put_env("AWS_ENDPOINT_URL_S3", old)
      else
        System.delete_env("AWS_ENDPOINT_URL_S3")
      end
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

  test "presign_url/1 upload" do
    options = [
      access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY")
    ]

    url = ReqS3.presign_url([url: "s3://wojtekmach-test/foo", method: :put] ++ options)
    body = "hi#{Time.utc_now()}"

    %{status: 200} =
      Req.put!(url, body: body)

    %{status: 200, body: ^body} =
      Req.get!("https://wojtekmach-test.s3.amazonaws.com/foo",
        aws_sigv4: [service: :s3] ++ options
      )
  end

  @tag :tmp_dir
  test "presign_form/1", %{tmp_dir: tmp_dir} do
    options = [
      access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY")
    ]

    bucket = System.fetch_env!("BUCKET_NAME")

    presign_options =
      options ++
        [
          bucket: bucket,
          key: "key1",
          content_type: "text/plain"
        ]

    form = ReqS3.presign_form(presign_options)
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
        aws_sigv4: [service: :s3] ++ options
      )
  end
end
