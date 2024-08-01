defmodule ReqS3.XML do
  @moduledoc false

  if System.otp_release() < "25" do
    # xmerl_sax_parser :disallow_entities requires OTP 25+
    raise "req_s3 requires OTP 25+"
  end

  @list_fields [
    {"ListBucketResult", "Contents"},
    {"ListVersionsResult", "Version"}
  ]

  @list_fields_skip [
    {"ListAllMyBucketsResult", "Buckets", "Bucket"}
  ]

  @doc """
  Parses S3 XML into maps, lists, and strings.

  This is a best effort parser, trying to return the most convenient representation. This is
  tricky because collections can be represented in multiple ways:

      <ListAllMyBucketsResult>
        <Buckets>
          <Bucket><Name>bucket1</Name></Bucket>
          <Bucket><Name>bucket2</Name></Bucket>
        </Buckets>
      </ListAllMyBucketResult>

      <ListBucketResult>
        <Name>bucket1</Name>
        <Contents><Key>key1</Key></Contents>
        <Contents><Key>key2</Key></Contents>
      </ListBucketResult>

  We handle `ListBucketResult/Contents`, `ListVersionsResult/Version`,
  `ListAllMyBucketsResult/Buckets/Bucket` (and possibly others in the future) in a particular
  way and have a best effort fallback.
  """
  def parse_s3(xml) do
    parse(xml, {nil, []}, fn
      {:start_element, name, _attributes}, {root, stack} ->
        {root || name, [{name, nil} | stack]}

      # Collect e.g. <ListBucketResults><Contents>...</Contents> into a "Contents" _list_.
      {:end_element, name}, {root, [{name, val}, {parent_name, parent_val} | stack]}
      when {root, name} in @list_fields ->
        parent_val = Map.update(parent_val || %{}, name, [val], &(&1 ++ [val]))
        {root, [{parent_name, parent_val} | stack]}

      # Collect e.g. <ListAllMyBucketsResult><Buckets><Bucket>...</Bucket> into a "Buckets" _list_
      # skipping "Bucket".
      {:end_element, name}, {root, [{name, val}, {parent_name, parent_val} | stack]}
      when {root, parent_name, name} in @list_fields_skip ->
        parent_val = (parent_val || []) ++ [val]
        {root, [{parent_name, parent_val} | stack]}

      {:end_element, name}, {root, stack} ->
        case stack do
          # Best effort: by default simply put name/value into parent map. If the parent
          # map already contains name, turn parent[name] into a list and keep appending.
          # The obvious caveat is we'd only turn parent[name] into a list on the second element,
          # hence if XML contained just one element for what is semantically a list, it will be
          # represented as a map, not a list with single map element. As we discover these,
          # let's update @list_fields and @list_fields_skip.
          [{^name, val}, {parent_name, parent_val} | stack] ->
            parent_val = Map.update(parent_val || %{}, name, val, &(List.wrap(&1) ++ [val]))
            {root, [{parent_name, parent_val} | stack]}

          [{name, val}] ->
            {root, %{name => val}}

          other ->
            raise """
            unexpected :end_element state:

            #{inspect(other, pretty: true)}
            """
        end

      {:characters, string}, {root, [{name, _} | stack]} ->
        {root, [{name, string} | stack]}

      other, {root, stack} ->
        raise """
        unexpected event:

        #{inspect(other, pretty: true)}

        root: #{root}

        stack:

        #{inspect(stack, pretty: true)}
        """
    end)
    |> elem(1)
  end

  @doc ~S'''
  Parses XML into "simple format".

  This is currently unused by ReqS3, it is just a demonstration of the underlying `parse/3`
  function.

  ## Examples

      iex> xml = """
      ...> <items>
      ...>   <item><a>1</a></item>
      ...>   <item><a>2</a></item>
      ...> </items>
      ...> """
      iex> ReqS3.XML.parse_simple(xml)
      {"items", [], [{"item", [], [{"a", [], ["1"]}]}, {"item", [], [{"a", [], ["2"]}]}]}
  '''
  def parse_simple(xml) do
    parse(xml, [], fn
      {:start_element, name, attributes}, stack ->
        [{name, attributes, []} | stack]

      {:end_element, name}, stack ->
        [{^name, attributes, content} | stack] = stack
        current = {name, attributes, Enum.reverse(content)}

        case stack do
          [] ->
            current

          [{parent_name, parent_attributes, parent_content} | rest] ->
            [{parent_name, parent_attributes, [current | parent_content]} | rest]
        end

      {:characters, string}, [{name, attributes, content} | stack] ->
        [{name, attributes, [string | content]} | stack]
    end)
  end

  def parse(xml, state, fun) do
    {:ok, %{state: state}, _leftover} =
      :xmerl_sax_parser.stream(
        xml,
        [
          :disallow_entities,
          event_fun: &process/3,
          event_state: %{
            state: state,
            fun: fun
          },
          external_entities: :none,
          fail_undeclared_ref: false
        ]
      )

    state
  end

  # https://www.erlang.org/doc/apps/xmerl/xmerl_sax_parser.html#t:event/0
  defp process(event, loc, state)

  defp process({:startElement, _uri, name, _qualified_name, attributes}, _loc, state) do
    attributes =
      for attribute <- attributes do
        {_, _, name, value} = attribute
        {List.to_string(name), List.to_string(value)}
      end

    %{state | state: state.fun.({:start_element, List.to_string(name), attributes}, state.state)}
  end

  defp process({:endElement, _uri, name, _qualified_name}, _loc, state) do
    %{state | state: state.fun.({:end_element, List.to_string(name)}, state.state)}
  end

  defp process({:characters, charlist}, _loc, state) do
    %{state | state: state.fun.({:characters, List.to_string(charlist)}, state.state)}
  end

  defp process(_event, _loc, state) do
    state
  end
end
