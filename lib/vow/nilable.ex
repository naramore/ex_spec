defmodule Vow.Nilable do
  @moduledoc false

  defstruct [:vow]

  @type t :: %__MODULE__{
          vow: Vow.t()
        }

  @spec new(Vow.t()) :: t
  def new(vow) do
    %__MODULE__{vow: vow}
  end

  defimpl Vow.Conformable do
    @moduledoc false

    def conform(_vow, _vow_path, _via, _value_path, nil) do
      {:ok, nil}
    end

    def conform(%@for{vow: vow}, vow_path, via, value_path, value) do
      @protocol.conform(vow, vow_path, via, value_path, value)
    end
  end
end
