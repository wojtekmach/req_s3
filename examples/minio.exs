# Start MINIO:
# $ docker run -p 9000:9000 \
#     -e MINIO_ROOT_USER=minio \
#     -e MINIO_ROOT_PASSWORD=minio123 \
#     minio/minio server /data

Mix.install([:req_s3])

req =
  Req.new()
  |> ReqS3.attach(
    aws_endpoint_url_s3: "http://localhost:9000",
    aws_sigv4: [
      access_key_id: "minio",
      secret_access_key: "minio123"
    ]
  )

if Req.get!(req, url: "s3://bucket1").status == 404 do
  %{status: 200} = Req.put!(req, url: "s3://bucket1")
end

%{status: 200} = Req.put!(req, url: "s3://bucket1/object1", body: "1")
%{status: 200} = Req.put!(req, url: "s3://bucket1/object2", body: "2")
%{status: 200, body: body} = Req.get!(req, url: "s3://bucket1")
dbg(body)
