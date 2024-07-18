# CHANGELOG

## v0.2.0 (2024-07-18)

  * Support Req v0.5.

  * Change decoded response for `s3://{bucket}` endpoint. Instead of listing
    just object keys, return decoded XML response.

  * Add [`ReqS3.presign_url/1`].

  * Add [`ReqS3.presign_form/1`].

## v0.1.1 (2023-09-01)

  * Support Req v0.4.

## v0.1.0 (2022-08-24)

  * Initial release

[`ReqS3.presign_url/1`]: https://hexdocs.pm/req_s3/ReqS3.html#presign_url/1
[`ReqS3.presign_form/1`]: https://hexdocs.pm/req_s3/ReqS3.html#presign_form/1
