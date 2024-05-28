# ReqS3

[Req](https://github.com/wojtekmach/req) plugin for [Amazon S3](https://aws.amazon.com/s3/) and S3-compatible services.

ReqS3 handles a custom `s3://` url scheme that supports these URLs:

```text
s3://<bucket>        # GET bucket items list
s3://<bucket>/<item> # GET/PUT bucket item
```

## Usage

```elixir
Mix.install([
  {:req, "~> 0.5.0"},
  {:req_s3, "~> 0.2.0"}
])

req = Req.new() |> ReqS3.attach()

Req.get!(req, url: "s3://ossci-datasets").body
#=>
# [
#   "mnist/",
#   "mnist/t10k-images-idx3-ubyte.gz",
#   "mnist/t10k-labels-idx1-ubyte.gz",
#   "mnist/train-images-idx3-ubyte.gz",
#   "mnist/train-labels-idx1-ubyte.gz"
# ]

body = Req.get!(req, url: "s3://ossci-datasets/mnist/t10k-images-idx3-ubyte.gz").body
<<_::32, n_images::32, n_rows::32, n_cols::32, _body::binary>> = body
{n_images, n_rows, n_cols}
#=> {10_000, 28, 28}
```

It can be also used to presign URLs:

```elixir
options = [
  access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY")
]

req = Req.new() |> ReqS3.attach()
Req.put!("s3://bucket1/key1", body: "Hello, World!", aws_sigv4: options)

presigned_url = ReqS3.presign_url("s3://bucket1/key1", options)
#=> "https://s3.amazonaws.com/bucket1/key1?X-Amz-Algorithm=AWS4-HMAC-SHA256&..."

Req.get!(presigned_url).body
#=> "Hello, World!"
```

## TODO

  * Add Phoenix Playground example.

  * Change "list bucket" to return all data, not just key names

## License

Copyright (c) 2021 Wojtek Mach

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
