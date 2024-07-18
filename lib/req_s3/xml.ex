defmodule ReqS3.XML do
  @moduledoc false

  def parse_s3_list_objects(xml) do
    case parse_simple(xml) do
      {"ListBucketResult", _, content} ->
        content =
          Enum.reduce(content, %{}, fn
            {"Contents", _attributes, content}, acc ->
              content =
                Enum.reduce(content, %{}, fn
                  {name, _attribute, value}, acc ->
                    Map.put(acc, name, value(value))
                end)

              Map.update(acc, "Contents", [content], &[content | &1])

            {name, _attribute, value}, acc ->
              Map.put(acc, name, value(value))
          end)

        content = Map.update!(content, "Contents", &Enum.reverse/1)
        %{"ListBucketResult" => content}

      _other ->
        xml
    end
  end

  defp value([]), do: nil
  defp value([value]), do: value

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
