defmodule ReqS3 do
  def run(request) when request.url.scheme == "s3" do
    host = "#{request.url.host}.s3.amazonaws.com"
    url = %{request.url | scheme: "https", host: host, authority: host, port: 443}
    headers = request.headers

    %{request | url: url, headers: headers}
    |> Req.append_response_steps([&decode/1])
  end

  def run(request) do
    request
  end

  require Record

  for {name, fields} <- Record.extract_all(from_lib: "xmerl/include/xmerl.hrl") do
    Record.defrecordp(name, fields)
  end

  defp decode({request, response}) do
    if request.url.path in [nil, "/"] do
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
