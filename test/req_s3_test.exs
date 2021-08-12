defmodule ReqS3Test do
  use ExUnit.Case
  doctest ReqS3

  test "list objects" do
    body = Req.get!("s3://ossci-datasets/", plugins: [ReqS3]).body
    assert "mnist/train-images-idx3-ubyte.gz" in body
  end

  test "get object" do
    body = Req.get!("s3://ossci-datasets/mnist/train-images-idx3-ubyte.gz", plugins: [ReqS3]).body
    <<_::32, n_images::32, n_rows::32, n_cols::32, _body::binary>> = body
    assert {n_images, n_rows, n_cols} == {60_000, 28, 28}
  end
end
