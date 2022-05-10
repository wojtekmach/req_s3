# ReqS3

[Req](https://github.com/wojtekmach/req_s3) plugin for [Amazon S3](https://aws.amazon.com/s3/).

ReqS3 handles a custom `s3://` url scheme that supports two endpoints:

```
s3://<bucket>        # list bucket items
s3://<bucket>/<item> # get item content
```

## Usage

```elixir
Mix.install([
  {:req, github: "wojtekmach/req"},
  {:req_s3, github: "wojtekmach/req_s3"}
])

req = Req.new() |> ReqS3.attach()
Req.get!(req, url: "s3://ossci-datasets").body
#=>
# [
#   "mnist/",
#   "mnist/t10k-images-idx3-ubyte.gz",
#   "mnist/t10k-labels-idx1-ubyte.gz",
#   "mnist/train-images-idx3-ubyte.gz",
#   "mnist/train-labels-idx1-ubyte.
# ]

req = Req.new() |> ReqS3.run()
body = Req.get!(req, url: "s3://ossci-datasets/mnist/train-images-idx3-ubyte.gz").body
<<_::32, n_images::32, n_rows::32, n_cols::32, _body::binary>> = body
{n_images, n_rows, n_cols}
#=> {60_000, 28, 28}
```
