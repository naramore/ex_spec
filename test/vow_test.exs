defmodule VowTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  import StreamData
  alias VowTestUtils, as: VTU
  doctest Vow

  describe "Vow.conform/2" do
    @tag skip: true
    property "returns" do
      check all vow <- VowData.vow(),
                value <- term(),
                max_runs: 25 do
        result = Vow.conform(vow, value)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end
  end

  describe "Vow.conform!/2" do
    property "should raise a ConformError if failed" do
      check all value <- term(), max_runs: 25 do
        vow = VowRef.none()

        assert_raise(Vow.ConformError, fn ->
          Vow.conform!(vow, value)
        end)
      end
    end

    property "should return value if conformed successfully" do
      check all value <- term() do
        vow = VowRef.any()
        assert value == Vow.conform!(vow, value)
      end
    end
  end

  describe "Vow.valid?/2" do
    property "should return true if value conforms to vow" do
      check all value <- term() do
        vow = VowRef.any()
        assert Vow.valid?(vow, value)
      end
    end

    property "should return false if value fails to conform to vow" do
      check all value <- term() do
        vow = VowRef.none()
        refute Vow.valid?(vow, value)
      end
    end
  end

  property "Vow.invalid?/2 should always return opposite of Vow.valid?/2" do
    check all value <- one_of([boolean(), integer(), float(), string(:ascii)]),
              vow <- VowData.non_recur_vow() do
      assert VTU.complement(Vow.invalid?(vow, value)) == Vow.valid?(vow, value)
    end
  end

  property "Vow.set/2 is a shortcut for MapSet.new/1" do
    check all values <- list_of(term()), max_runs: 50 do
      assert Vow.set(values) == MapSet.new(values)
    end
  end

  describe "Vow.also/1" do
    property "w/ 2 vows behaves identically to Vow.also/2" do
      check all vow1 <- VowData.also(VowData.non_recur_vow()),
                vow2 <- VowData.also(VowData.non_recur_vow()),
                value <- one_of([integer(), float(), boolean(), string(:ascii)]),
                max_runs: 25 do
        also1 = Vow.also(vow1, vow2)
        also2 = Vow.also([vow1, vow2])
        assert Vow.conform(also1, value) == Vow.conform(also2, value)
      end
    end

    property "should always conform given zero vows" do
      check all value <- term() do
        vow = Vow.also([])
        assert match?({:ok, ^value}, Vow.conform(vow, value))
      end
    end

    property "given one vow should conform to the same value as that vow" do
      check all {ivow, vow} <- map(VowData.non_recur_vow(), &{&1, Vow.also([&1])}),
                value <- term() do
        result = Vow.conform(vow, value) |> VTU.strip_vow()
        iresult = Vow.conform(ivow, value) |> VTU.strip_vow()
        assert result == iresult
      end
    end

    property "if all vows conform -> also conforms (numbers)" do
      check all {min, max} <- tuple({integer(0..100), integer(101..200)}),
                value <- one_of([integer(min..max), float(min: min, max: max)]) do
        vow = Vow.also([&is_number/1, &(&1 >= min), &(&1 <= max)])
        assert match?({:ok, ^value}, Vow.conform(vow, value))
      end
    end

    property "if all vows conform -> also conforms (lists)" do
      check all value <- list_of(string(:ascii, min_length: 1)) do
        vow =
          Vow.also([
            Vow.list_of(&is_bitstring/1),
            &Enum.all?(&1, fn x -> String.length(x) > 0 end)
          ])

        assert match?({:ok, ^value}, Vow.conform(vow, value))
      end
    end

    property "if any vows fail to conform -> also fails" do
      check all value <- one_of([integer(), float()]) do
        vow = Vow.also([&is_number/1, &(not is_number(&1))])
        assert match?({:error, _}, Vow.conform(vow, value))
      end
    end

    property "recursively feeds 'conformed' values into the next vows" do
      check all value <- one_of([integer(), float(), boolean(), atom(:alphanumeric)]) do
        vow =
          Vow.also([
            Vow.one_of(
              i: &is_integer/1,
              b: &is_boolean/1,
              a: &is_atom/1,
              f: &is_float/1
            ),
            Vow.map_of(&is_atom/1, fn _ -> true end)
          ])

        assert match?({:ok, _}, Vow.conform(vow, value))
      end
    end
  end

  describe "Vow.one_of/1" do
    test "cannot create with no options" do
      assert_raise(FunctionClauseError, fn ->
        Vow.one_of([])
      end)
    end

    property "duplicate keys -> raise Vow.DuplicateNameError" do
      check all ks <- uniq_list_of(atom(:alphanumeric), min_length: 2),
                keys <- member_of(ks) |> map(fn k -> [k | ks] end) do
        vows = Enum.zip(keys, Stream.repeatedly(fn -> nil end))

        assert_raise(Vow.DuplicateNameError, fn ->
          Vow.one_of(vows)
        end)
      end
    end

    property "given one vow should conform to the same value as that vow wrapped in a map" do
      check all {k, i} <- tuple({atom(:alphanumeric), integer()}) do
        ivow = &is_integer/1
        vow = Vow.one_of([{k, ivow}])
        assert match?({:ok, %{^k => ^i}}, Vow.conform(vow, i))
        assert match?({:ok, ^i}, Vow.conform(ivow, i))
      end
    end

    property "if at least one vow conforms -> one_of conforms" do
      check all value <- one_of([integer(), float(), boolean(), atom(:alphanumeric)]) do
        vow =
          Vow.one_of(
            i: &is_integer/1,
            b: &is_boolean/1,
            a: &is_atom/1,
            f: &is_float/1
          )

        assert match?({:ok, _}, Vow.conform(vow, value))
      end
    end

    property "conforms to the 1st vow that accepts the value" do
      check all value <- one_of([integer(), float()]) do
        vow =
          Vow.one_of(
            n: &is_number/1,
            i: &is_integer/1,
            f: &is_float/1
          )

        assert match?({:ok, %{n: ^value}}, Vow.conform(vow, value))
      end
    end

    property "fails if all subvows fail" do
      check all value <- one_of([integer(), float()]) do
        vow =
          Vow.one_of(
            a: &is_atom/1,
            b: &is_boolean/1
          )

        assert match?({:error, _}, Vow.conform(vow, value))
      end
    end
  end

  describe "Vow.nilable/1" do
    property "conforms successfully if value is nil" do
      check all vow <- map(VowData.vow(), &Vow.nilable/1) do
        assert match?({:ok, _}, Vow.conform(vow, nil))
      end
    end

    property "conform on the nilable is equivalent to conform of subvow otherwise" do
      check all vow <- VowData.nilable(VowData.non_recur_vow()),
                value <- one_of([boolean(), integer(), float(), string(:ascii)]) do
        nilable = Vow.conform(vow, value) |> VTU.strip_vow()
        subvow = Vow.conform(vow.vow, value) |> VTU.strip_vow()
        assert nilable == subvow
      end
    end
  end

  describe "Vow.list_of/2" do
    property "if value is not a list -> error" do
      check all value <- filter(term(), &(not is_list(&1))),
                vow <- VowData.list_of(),
                max_runs: 25 do
        assert match?({:error, _}, Vow.conform(vow, value))
      end
    end

    property "if value is improper list -> error" do
      check all value <-
                  list_of(constant(nil), min_length: 1)
                  |> map(&VTU.to_improper/1),
                vow <- VowData.list_of() do
        assert match?({:error, _}, Vow.conform(vow, value))
      end
    end

    property "if value is larger then max length -> error" do
      check all {max, vow} <-
                  integer(0..20) |> map(fn x -> {x, Vow.list_of(&Vow.any?/1, max_length: x)} end),
                value <- list_of(constant(nil), min_length: max + 1) do
        assert match?({:error, _}, Vow.conform(vow, value))
      end
    end

    property "if value is smaller then min length -> error" do
      check all {min, vow} <-
                  integer(5..20) |> map(fn x -> {x, Vow.list_of(&Vow.any?/1, min_length: x)} end),
                value <- list_of(constant(nil), max_length: min - 1) do
        assert match?({:error, _}, Vow.conform(vow, value))
      end
    end

    property "if value does not contain unique elements and distinct?: true -> error" do
      check all value <- list_of(integer(), min_length: 2),
                index <- integer(0..length(value)),
                elem <- member_of(value),
                value = List.insert_at(value, index, elem) do
        vow = Vow.list_of(&is_integer/1, distinct?: true)
        assert match?({:error, _}, Vow.conform(vow, value))
      end
    end

    property "if at least one element in value does not conform -> list_of errors" do
      check all value <- list_of(integer()),
                index <- integer(0..length(value)),
                elem <- atom(:alphanumeric),
                value = List.insert_at(value, index, elem) do
        vow = Vow.list_of(&is_integer/1)
        assert match?({:error, _}, Vow.conform(vow, value))
      end
    end

    property "if all elements in value conform to subvow -> list_of conforms" do
      check all value <- list_of(integer()) do
        vow = Vow.list_of(&is_integer/1)
        assert match?({:ok, ^value}, Vow.conform(vow, value))
      end
    end
  end

  describe "Vow.map_of/3" do
    property "if value is not a map -> error" do
      check all value <- filter(term(), &(not is_map(&1))), vow <- VowData.map_of(), max_runs: 25 do
        assert match?({:error, _}, Vow.conform(vow, value))
      end
    end

    property "if at least one kv-pair in value does not conform -> map_of errors" do
      check all value <- map_of(atom(:alphanumeric), integer()),
                k <- filter(atom(:alphanumeric), &(&1 not in Map.keys(value))),
                v <- atom(:alphanumeric),
                value = Map.put(value, k, v) do
        vow = Vow.map_of(&is_atom/1, &is_integer/1)
        assert match?({:error, _}, Vow.conform(vow, value))
      end
    end

    property "if all elements in value conform to subvow -> map_of conforms" do
      check all value <- map_of(atom(:alphanumeric), integer()) do
        vow = Vow.map_of(&is_atom/1, &is_integer/1)
        assert match?({:ok, ^value}, Vow.conform(vow, value))
      end
    end

    property "conform_keys?: true forces the map keys to be conformed" do
      check all value <-
                  map_of(
                    one_of([atom(:alphanumeric), string(:ascii)]),
                    integer(),
                    min_length: 1
                  ) do
        vow =
          Vow.map_of(
            Vow.one_of(a: &is_atom/1, s: &is_bitstring/1),
            &is_integer/1,
            conform_keys?: true
          )

        result = Vow.conform(vow, value)
        assert match?({:ok, _}, result)
        refute match?({:ok, ^value}, result)
      end
    end

    property "conform_keys?: false does not change keys" do
      check all value <-
                  map_of(
                    one_of([atom(:alphanumeric), string(:ascii)]),
                    integer()
                  ) do
        vow =
          Vow.map_of(
            Vow.one_of(a: &is_atom/1, s: &is_bitstring/1),
            &is_integer/1,
            conform_keys?: false
          )

        assert match?({:ok, ^value}, Vow.conform(vow, value))
      end
    end

    property "if key vow is simple -> conform_keys? does nothing" do
      check all value <- map_of(string(:ascii), integer()),
                conform_keys? <- boolean() do
        vow = Vow.map_of(&is_bitstring/1, &is_integer/1, conform_keys?: conform_keys?)
        assert match?({:ok, ^value}, Vow.conform(vow, value))
      end
    end

    property "if value is larger then max length -> error" do
      check all {max, vow} <-
                  integer(0..20)
                  |> map(fn x -> {x, Vow.map_of(&Vow.any?/1, &Vow.any?/1, max_length: x)} end),
                value <- map_of(atom(:alphanumeric), constant(nil), min_length: max + 1) do
        assert match?({:error, _}, Vow.conform(vow, value))
      end
    end

    property "if value is smaller then min length -> error" do
      check all {min, vow} <-
                  integer(5..20)
                  |> map(fn x -> {x, Vow.map_of(&Vow.any?/1, &Vow.any?/1, min_length: x)} end),
                value <- map_of(atom(:alphanumeric), constant(nil), max_length: min - 1) do
        assert match?({:error, _}, Vow.conform(vow, value))
      end
    end
  end

  describe "Vow.keyword_of/2" do
    property "succeeds if value valid keyword list" do
      check all value <- keyword_of(integer()) do
        vow = Vow.keyword_of(&is_integer/1)
        assert match?({:ok, ^value}, Vow.conform(vow, value))
      end
    end
  end
end
