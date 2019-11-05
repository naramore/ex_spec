defmodule Vow.FunctionWrapper do
  @moduledoc """
  TODO
  """

  defstruct function: nil,
            form: nil,
            bindings: []

  @type t :: %__MODULE__{
          function: (term -> boolean),
          form: Macro.t(),
          bindings: keyword()
        }

  @doc false
  @spec new((term -> boolean), Macro.t(), keyword()) :: t
  def new(function, form, bindings \\ []) do
    %__MODULE__{
      function: function,
      form: form,
      bindings: bindings
    }
  end

  @doc """
  """
  @spec wrap(Macro.t(), keyword()) :: Macro.t()
  defmacro wrap(quoted, bindings \\ []) do
    quote do
      Vow.FunctionWrapper.new(
        unquote(quoted),
        unquote(Macro.escape(quoted)),
        unquote(bindings)
      )
    end
  end

  # coveralls-ignore-start
  defimpl Inspect do
    @moduledoc false

    def inspect(%@for{form: form, bindings: bindings}, opts) do
      Macro.to_string(form, fn
        {var, _, mod}, string when is_atom(var) and is_atom(mod) ->
          if Keyword.has_key?(bindings, var) do
            Keyword.get(bindings, var)
            |> Kernel.inspect(opts_to_keyword(opts))
          else
            string
          end

        _ast, string ->
          string
      end)
    end

    @spec opts_to_keyword(Inspect.Opts.t()) :: keyword
    defp opts_to_keyword(opts) do
      opts
      |> Map.from_struct()
      |> Enum.into([])
    end
  end

  # coveralls-ignore-stop

  defimpl Vow.Conformable do
    @moduledoc false

    @impl Vow.Conformable
    def conform(%@for{function: fun} = func, vow_path, via, value_path, value) do
      case @protocol.Function.conform(fun, vow_path, via, value_path, value) do
        {:ok, conformed} ->
          {:ok, conformed}

        {:error, [%{predicate: ^fun} = problem]} ->
          {:error, [%{problem | predicate: func.form}]}

        {:error, problems} ->
          {:error, problems}
      end
    end

    @impl Vow.Conformable
    def unform(_vow, value), do: {:ok, value}
  end

  if Code.ensure_loaded?(StreamData) do
    defimpl Vow.Generatable do
      @moduledoc false

      @impl Vow.Generatable
      def gen(vow) do
        @protocol.Function.gen(vow)
      end
    end
  end
end