defmodule Vow do
  @moduledoc """
  TODO
  """

  import Kernel, except: [get_in: 2, update_in: 3, put_in: 3]
  alias Vow.{Conformable, ConformError}

  @typedoc """
  """
  @type t :: Conformable.t()

  @doc """
  """
  @spec conform(t, value :: term) :: {:ok, Conformable.conformed()} | {:error, ConformError.t()}
  def conform(vow, value) do
    case Conformable.conform(vow, [], [], [], value) do
      {:ok, conformed} ->
        {:ok, conformed}

      {:error, problems} ->
        {:error, ConformError.new(problems, vow, value)}
    end
  end

  @doc """
  """
  @spec conform!(t, value :: term) :: Conformable.conformed() | no_return
  def conform!(vow, value) do
    case conform(vow, value) do
      {:ok, conformed} -> conformed
      {:error, reason} -> raise reason
    end
  end

  @doc """
  """
  @spec valid?(t, value :: term) :: boolean
  def valid?(vow, value) do
    case conform(vow, value) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  """
  @spec invalid?(t, value :: term) :: boolean
  def invalid?(vow, value) do
    not valid?(vow, value)
  end

  defdelegate unform(vow, value), to: Vow.Conformable

  @doc """
  """
  @spec get_in(t, path :: [term]) :: t | nil
  def get_in(vow, []), do: vow
  def get_in(vow, path) do
    try do
      Kernel.get_in(vow, Enum.map(path, &lazy_path/1))
    rescue
      _ -> nil
    end
  end

  @doc """
  """
  @spec update_in(t, path :: [term], (term -> term)) :: t
  def update_in(vow, [], fun), do: fun.(vow)
  def update_in(vow, path, fun) do
    try do
      Kernel.update_in(vow, Enum.map(path, &lazy_path/1), fun)
    rescue
      _ -> vow
    end
  end

  @doc """
  """
  @spec put_in(t, path :: [term], value :: term) :: t
  def put_in(vow, path, value) do
    update_in(vow, path, fn _ -> value end)
  end

  @doc false
  @spec lazy_path(term) :: Access.access_fun(t, term)
  defp lazy_path(fun) when is_function(fun, 3), do: fun
  defp lazy_path(i) when is_integer(i) do
    fn
      type, data, next when is_list(data) ->
        Access.at(i).(type, data, next)
      type, data, next when is_tuple(data) ->
        Access.elem(i).(type, data, next)
      type, data, next ->
        Access.key(i).(type, data, next)
    end
  end
  defp lazy_path(key) do
    fn type, data, next ->
      Access.key(key).(type, data, next)
    end
  end

  @type generator :: Vow.Generatable.generator
  @type gen_fun :: (() -> generator)
  @type override :: {path :: [term], gen_fun}

  @doc """
  """
  @spec gen(t, [override]) :: {:ok, generator} | {:error, reason :: term}
  def gen(vow, overrides \\ []) do
    Enum.reduce(overrides, vow, fn {path, gen_fun}, acc ->
      put_in(acc, path, gen_fun.())
    end)
    |> Vow.Generatable.gen()
  end

  @doc """
  """
  @spec unform!(t, Conformable.conformed()) :: value :: term | no_return
  def unform!(vow, value) do
    case unform(vow, value) do
      {:ok, unformed} -> unformed
      {:error, reason} -> raise reason
    end
  end

  @doc """
  """
  @spec set(Enum.t()) :: MapSet.t()
  def set(enumerable), do: MapSet.new(enumerable)

  @doc """
  """
  @spec term?(term) :: boolean
  def term?(_term), do: true

  @doc """
  """
  @spec any?(term) :: boolean
  def any?(term), do: term?(term)

  @doc """
  """
  @spec also([t]) :: t
  def also(vows) do
    Vow.Also.new(vows)
  end

  @doc """
  """
  @spec also(t, t) :: t
  def also(vow1, vow2) do
    also([vow1, vow2])
  end

  @doc """
  """
  @spec one_of([{atom, t}, ...]) :: t | no_return
  def one_of(named_vows)
      when is_list(named_vows) and length(named_vows) > 0 do
    Vow.OneOf.new(named_vows)
  end

  @doc """
  """
  @spec nilable(t) :: t
  def nilable(vow) do
    Vow.Nilable.new(vow)
  end

  @typedoc """
  """
  @type list_opt ::
          {:length, Range.t() | non_neg_integer}
          | {:min_length, non_neg_integer}
          | {:max_length, non_neg_integer}
          | {:distinct?, boolean}

  @typedoc """
  """
  @type list_opts :: [list_opt]

  @doc """
  """
  @spec list_of(t, list_opts) :: t
  def list_of(vow, opts \\ []) do
    distinct? = Keyword.get(opts, :distinct?, false)
    {min, max} = get_range(opts)
    Vow.List.new(vow, min, max, distinct?)
  end

  @doc false
  @spec get_range(list_opts) :: {non_neg_integer, non_neg_integer | nil}
  defp get_range(opts) do
    with {:length, nil} <- {:length, Keyword.get(opts, :length)},
         {:min, min} <- {:min, Keyword.get(opts, :min_length, 0)},
         {:max, max} <- {:max, Keyword.get(opts, :max_length)} do
      {min, max}
    else
      {:length, min..max} -> {min, max}
      {:length, len} -> {len, len}
    end
  end

  @doc """
  """
  @spec keyword_of(t, list_opts) :: t
  def keyword_of(vow, opts \\ []) do
    list_of({&is_atom/1, vow}, opts)
  end

  @typedoc """
  """
  @type map_opt ::
          list_opt
          | {:conform_keys?, boolean}

  @typedoc """
  """
  @type map_opts :: [map_opt]

  @doc """
  """
  @spec map_of(key_vow :: t, value_vow :: t, map_opts) :: t
  def map_of(key_vow, value_vow, opts \\ []) do
    conform_keys? = Keyword.get(opts, :conform_keys?, false)
    {min, max} = get_range(opts)
    Vow.Map.new(key_vow, value_vow, min, max, conform_keys?)
  end

  @typedoc """
  """
  @type merged ::
          Vow.Merge.t()
          | Vow.Map.t()
          | Vow.Keys.t()
          | map

  @doc """
  """
  @spec merge([merged]) :: t
  def merge(vows) do
    Vow.Merge.new(vows)
  end

  @typedoc """
  """
  @type vow_ref :: atom | {module, atom} | Vow.Ref.t()

  @typedoc """
  """
  @type vow_ref_expr ::
          vow_ref
          | {:and | :or, [vow_ref_expr, ...]}

  @typedoc """
  """
  @type key_opt ::
          {:required, [vow_ref_expr]}
          | {:optional, [vow_ref_expr]}
          | {:default_module, module | nil}

  @typedoc """
  """
  @type key_opts :: [key_opt]

  @doc """
  """
  @spec keys(key_opts) :: t | no_return
  def keys(opts) do
    required = Keyword.get(opts, :required, [])
    optional = Keyword.get(opts, :optional, [])
    default_module = Keyword.get(opts, :default_module, nil)
    Vow.Keys.new(required, optional, default_module)
  end

  @doc """
  """
  @spec mkeys(key_opts) :: Macro.t()
  defmacro mkeys(opts) do
    opts = Keyword.put(opts, :default_module, __CALLER__.module)

    quote do
      Vow.keys(unquote(opts))
    end
  end

  @doc """
  """
  @spec regex?(t) :: boolean
  def regex?(vow) do
    case Vow.RegexOperator.impl_for(vow) do
      nil -> false
      _ -> true
    end
  end

  @doc """
  """
  @spec amp([t]) :: t
  def amp(vows) do
    Vow.Amp.new(vows)
  end

  @doc """
  """
  @spec amp(t, t) :: t
  def amp(vow1, vow2) do
    amp([vow1, vow2])
  end

  @doc """
  """
  @spec maybe(t) :: t
  def maybe(vow) do
    Vow.Maybe.new(vow)
  end

  @doc """
  """
  @spec one_or_more(t) :: t
  def one_or_more(vow) do
    Vow.OneOrMore.new(vow)
  end

  @doc """
  """
  @spec oom(t) :: t
  def oom(vow), do: one_or_more(vow)

  @doc """
  """
  @spec zero_or_more(t) :: t
  def zero_or_more(vow) do
    Vow.ZeroOrMore.new(vow)
  end

  @doc """
  """
  @spec zom(t) :: t
  def zom(vow), do: zero_or_more(vow)

  @doc """
  """
  @spec alt([{atom, t}, ...]) :: t | no_return
  def alt(named_vows)
      when is_list(named_vows) and length(named_vows) > 0 do
    Vow.Alt.new(named_vows)
  end

  @doc """
  """
  @spec cat([{atom, t}, ...]) :: t | no_return
  def cat(named_vows)
      when is_list(named_vows) and length(named_vows) > 0 do
    Vow.Cat.new(named_vows)
  end

  @typedoc """
  """
  @type fvow_opt ::
          {:args, [t]}
          | {:ret, t}
          | {:fun, t}

  @typedoc """
  """
  @type fvow_opts :: [fvow_opt]

  @doc """
  """
  @spec fvow(fvow_opts) :: t
  def fvow(opts) do
    args = Keyword.get(opts, :args)
    ret = Keyword.get(opts, :ret)
    fun = Keyword.get(opts, :fun)
    Vow.Function.new(args, ret, fun)
  end

  defdelegate conform_function(vow, function, args \\ []), to: Vow.Function, as: :conform
end
