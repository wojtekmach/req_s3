# ReqS3

[![CI](https://github.com/wojtekmach/req_s3/actions/workflows/ci.yml/badge.svg)](https://github.com/wojtekmach/req_s3/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/req_s3.svg)](https://github.com/wojtekmach/req_s3/blob/main/LICENSE.md)
[![Version](https://img.shields.io/hexpm/v/req_s3.svg)](https://hex.pm/packages/req_s3)
[![Hex Docs](https://img.shields.io/badge/documentation-gray.svg)](https://hexdocs.pm/req_s3)

[Req](https://github.com/wojtekmach/req) plugin for [Amazon S3](https://aws.amazon.com/s3/) and S3-compatible services.

<!-- MDOC !-->

ReqS3 handles a custom `s3://` url scheme. Example requests are:

```elixir
# list buckets
Req.get!(req, url: "s3://")

# list objects
Req.get!(req, url: "s3://#{bucket}")

# get object
Req.get!(req, url: "s3://#{bucket}/#{key}")

# put object
Req.put!(req, url: "s3://#{bucket}/#{key}")
```

The responses for listing buckets and objects are automatically decoded.

## Usage

```elixir
Mix.install([
  {:req, "~> 0.5.0"},
  {:req_s3, "~> 0.2.3"}
])

req = Req.new() |> ReqS3.attach()

Req.get!(req, url: "s3://ossci-datasets").body
#=>
# %{
#   "ListBucketResult" => %{
#     "Contents" => [
#       %{"Key" => "mnist/", ...},
#       %{"Key" => "mnist/t10k-images-idx3-ubyte.gz", ...},
#       ...
#     ],
#     "Name" => "ossci-datasets",
#     ...
#   }
# }

body = Req.get!(req, url: "s3://ossci-datasets/mnist/t10k-images-idx3-ubyte.gz").body
<<_::32, n_images::32, n_rows::32, n_cols::32, _body::binary>> = body
{n_images, n_rows, n_cols}
#=> {10_000, 28, 28}
```

## Examples

  * [MNIST](examples/mnist.livemd)

  * [S3 Direct Upload](examples/upload.livemd)

  * [MINIO](examples/minio.exs)

```sh
$ docker run -p 9000:9000 \
   -e MINIO_ROOT_USER=minio \
   -e MINIO_ROOT_PASSWORD=minio123 \
   minio/minio server /data
```

### Pre-signing

ReqS3 can be used to presign URLs:

```elixir
options = [
  access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY")
]

req = Req.new() |> ReqS3.attach(aws_sigv4: options)
%{status: 200} = Req.put!(req, url: "s3://bucket1/key1", body: "Hello, World!")

presigned_url = ReqS3.presign_url([bucket: "bucket1", key: "key1"] ++ options)
#=> "https://bucket1.s3.amazonaws.com/key1?X-Amz-Algorithm=AWS4-HMAC-SHA256&..."

Req.get!(presigned_url).body
#=> "Hello, World!"
```

and form uploads:

```elixir
form = ReqS3.presign_form([bucket: "bucket1", key: "key1"] ++ options)
%{status: 204} = Req.post!(form.url, form_multipart: [file: "Hello, World!"] ++ form.fields)

Req.get!(presigned_url).body
#=> "Hello, World!"
```

## Environment Variables

ReqS3 supports the following standardised system environment variables:

  * `AWS_ACCESS_KEY_ID`

  * `AWS_SECRET_ACCESS_KEY`

  * `AWS_REGION`

  * `AWS_ENDPOINT_URL_S3`

<!-- MDOC !-->

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
