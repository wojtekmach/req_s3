defmodule ReqS3 do
  def run(request, _opts) when request.uri.scheme == "s3" do
    host = "#{request.uri.host}.s3.amazonaws.com"
    uri = %{request.uri | scheme: "https", host: host, authority: host, port: 443}
    headers = request.headers

    %{request | uri: uri, headers: headers}
    |> Req.append_response_steps([&ReqS3.decode/2])
  end

  def run(request, _opts) do
    request
  end

  require Record

  for {name, fields} <- Record.extract_all(from_lib: "xmerl/include/xmerl.hrl") do
    Record.defrecordp(name, fields)
  end

  @doc false
  def decode(request, response) do
    if request.uri.path in [nil, "/"] do
      opts = [space: :normalize, comments: false, encoding: :latin1]
      {doc, ''} = :xmerl_scan.string(String.to_charlist(response.body), opts)
      list = :xmerl_xpath.string('//ListBucketResult/Contents/Key/text()', doc)

      body =
        for xmlText(value: value) <- list do
          List.to_string(value)
        end

      {request, put_in(response.body, body)}
    else
      {request, response}
    end
  end
end
