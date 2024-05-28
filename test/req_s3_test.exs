defmodule ReqS3Test do
  use ExUnit.Case, async: true

  doctest ReqS3, tags: [:integration], except: [presign_form: 1]

  setup_all do
    if System.get_env("AWS_ACCESS_KEY_ID") do
      options = [
        service: "s3",
        access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
        secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY")
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

  test "list objects" do
    req =
      Req.new()
      |> ReqS3.attach()

    body = Req.get!(req, url: "s3://ossci-datasets").body
    assert "mnist/t10k-images-idx3-ubyte.gz" in body
  end

  test "presign_url/2" do
    options = [
      access_key_id: "foo",
      secret_access_key: "bar"
    ]

    assert "https://wojtekmach-test.s3.amazonaws.com/foo?X-Amz-Algorithm=AWS4-HMAC-SHA256&" <> _ =
             ReqS3.presign_url("s3://wojtekmach-test/foo", options)
  end

  test "presign_form/2" do
  end
end
