defmodule ReqS3Test do
  use ExUnit.Case, async: true
  doctest ReqS3

  test "list objects" do
    req =
      Req.new(cache: true)
      |> ReqS3.attach()

    body = Req.get!(req, url: "s3://ossci-datasets").body
    assert "mnist/train-images-idx3-ubyte.gz" in body
  end
end
