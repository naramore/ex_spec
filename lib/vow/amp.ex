defmodule Vow.Amp do
  @moduledoc false

  defstruct [:vows]

  @type t :: %__MODULE__{
          vows: [{atom, Vow.t()}]
        }

  @spec new([Vow.t()]) :: t
  def new(vows) do
    %__MODULE__{vows: vows}
  end

  defimpl Vow.RegexOperator do
    @moduledoc false

    import Vow.Conformable.Vow.List, only: [proper_list?: 1]
    alias Vow.{Conformable, ConformError, RegexOp}

    def conform(%@for{vows: []}, _vow_path, _via, _value_path, value)
        when is_list(value) and length(value) >= 0 do
      {:ok, value, []}
    end

    def conform(%@for{vows: vows}, vow_path, via, value_path, value)
        when is_list(value) and length(value) >= 0 do
      Enum.reduce(vows, {:ok, value, []}, fn
        _, {:error, pblms} ->
          {:error, pblms}

        s, {:ok, c, rest} ->
          case conform_impl(s, vow_path, via, value_path, c) do
            {:ok, conformed, tail} -> {:ok, conformed, tail ++ rest}
            {:error, problems} -> {:error, problems}
          end
      end)
    end

    def conform(_vow, vow_path, via, value_path, value) when is_list(value) do
      {:error,
       [
         ConformError.new_problem(
           &proper_list?/1,
           vow_path,
           via,
           RegexOp.uninit_path(value_path),
           value
         )
       ]}
    end

    def conform(_vow, vow_path, via, value_path, value) do
      {:error,
       [
         ConformError.new_problem(
           &is_list/1,
           vow_path,
           via,
           RegexOp.uninit_path(value_path),
           value
         )
       ]}
    end

    defp conform_impl(vow, vow_path, via, value_path, value) do
      if Vow.regex?(vow) do
        @protocol.conform(vow, vow_path, via, value_path, value)
      else
        case Conformable.conform(vow, vow_path, via, RegexOp.uninit_path(value_path), value) do
          {:ok, conformed} -> {:ok, [conformed], []}
          {:error, problems} -> {:error, problems}
        end
      end
    end
  end
end
