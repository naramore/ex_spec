defmodule VowTestUtils do
  @moduledoc false

  @type conform_result :: {:ok, conformed :: term} | {:error, Vow.ConformError.t}

  @spec strip_spec(conform_result) :: conform_result
  def strip_spec({:ok, _} = result), do: result

  def strip_spec({:error, error}) do
    {:error, %{error | spec: nil}}
  end

  @spec strip_via(conform_result) :: conform_result
  def strip_via({:ok, _} = result), do: result

  def strip_via({:error, error}) do
    problems = Enum.map(error.problems, &%{&1 | via: []})
    {:error, %{error | problems: problems}}
  end

  @spec strip_via_and_spec(conform_result) :: conform_result
  def strip_via_and_spec(result) do
    result
    |> strip_via()
    |> strip_spec()
  end

  @spec to_improper([term, ...]) :: maybe_improper_list(term, term) | nil
  def to_improper([]), do: nil
  def to_improper([h|t]), do: [h | to_improper(t)]
end
