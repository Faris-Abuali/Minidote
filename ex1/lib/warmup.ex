defmodule Warmup do
  @spec add(number(), number()) :: number()
  def add(x, y) do
    x + y
  end

  @spec minimum(number(), number()) :: number()
  def minimum(x, y) when x < y do
    x
  end

  def minimum(_, y) do
    y
  end

  @spec swap({a, b}) :: {b, a} when a: var, b: var
  def swap({x, y}) do
    {y, x}
  end

  @spec swap({a, b, c}) :: {c, b, a} when a: var, b: var, c: var
  def swap({x, y, z}) do
    {z, y, x}
  end

  @spec swap(tuple()) :: tuple()
  def swap(ts) do
    first = elem(ts, 0)
    last = elem(ts, tuple_size(ts) - 1)
    Tuple.insert_at(Tuple.append(ts, first), 0, last)
  end

  @spec only_integers?(list(any())) :: boolean()
  def only_integers?([]) do
    true
  end

  def only_integers?([x | _]) when not is_integer(x) do
    false
  end

  def only_integers?([_ | xs]) do
    only_integers?(xs)
  end

  @spec delete(atom(), list({atom(), any()})) :: :noop | {:ok, list({atom(), any()})}
  def delete(_, []) do
    :noop
  end

  def delete(target, [{target, _} | rest]) do
    {:ok, rest}
  end

  def delete(target, [{key, value} | rest]) do
    case delete(target, rest) do
      {:ok, result} -> {:ok, [{key, value} | result]}
      :noop -> :noop
    end
  end

  @spec same?(any(), any()) :: boolean()
  def same?(x, x) do
    true
  end

  def same?(_, _) do
    false
  end

  # NOTE: There does seem to be a function in the Erlang standard library that performs reference equality (:erts_debug.same/2).
  # Still, it is best avoided, lest we venture into the perilous word without the gurantee of referential transparency.

  # iex(1)> defmodule Unsafe do def same?(a, b) do :erts_debug.same(a, b) end end
  # iex(2)> Unsafe.same? {1, 2}, {1, 2}
  # false
  # iex(3)> a = {1, 2}
  # {1, 2}
  # iex(4)> Unsafe.same? a, a
  # true

  @spec positive(list(number())) :: list(number())
  def positive(xs) do
    Enum.filter(xs, fn x -> x >= 0 end)
  end

  @spec all_positive?(list(number())) :: boolean()
  def all_positive?(xs) do
    Enum.all?(xs, fn x -> x >= 0 end)
  end

  @spec values(list({atom(), any()})) :: list(any())
  def values(kvs) do
    Enum.map(kvs, fn {_, v} -> v end)
  end

  @spec list_min(nonempty_list(number())) :: number()
  def list_min([x | xs]) do
    List.foldl(xs, x, &minimum/2)
  end

  # TODO: Exhaustively benchmark this against the other two impls
  # Uses the expanded form of "Matrix exponentation": https://www.nayuki.io/page/fast-fibonacci-algorithms

  @spec fib(integer()) :: integer()
  def fib(n) do
    {x, _} = do_fib(n)
    x
  end

  defp do_fib(0) do
    {0, 1}
  end

  defp do_fib(n) do
    # TODO: Benchmark Bitwise.bsl vs * and Bitwise.bsr vs /
    # The compiler doesn't seem to perform strength reduction either.
    # So no optimization of patterns like (_ * 2) into (_ << 1). :(
    # On the bytecode level, both call their respective BIFs.
    # https://godbolt.org/z/rqhbY4nb7
    # Although, this might also have unexpected behavior when receiving negative/large args.
    # {a, b} = do_fib(div(n, 2))
    {a, b} = do_fib(Bitwise.bsr(n, 1))
    # c = a * (b * 2 - a)
    c = a * (Bitwise.bsl(b, 1) - a)
    d = a * a + b * b

    # case rem(n, 2) do
    case Bitwise.band(n, 1) do
      0 -> {c, d}
      _ -> {d, c + d}
    end
  end

  # Unsurprisingly, Dialyzer flags most functions in the Corecursion section as having non-sensical types.
  def alternating_list do
    [1, 0, -1 | &alternating_list/0]
  end

  def one_two_l2 do
    [1, 2, &one_neg_one_l2/0]
  end

  def one_neg_one_l2 do
    [1, -1 | &one_neg_one_l2/0]
  end

  @spec has0(list(any())) :: boolean()
  def has0(xs) do
    do_has0(xs, [])
  end

  defp do_has0([x | xs], seen) when is_integer(x) do
    x === 0 || do_has0(xs, seen)
  end

  defp do_has0([f | _], seen) do
    f_hash = :erlang.phash2(f)

    seen_f_before =
      Enum.any?(seen, fn g_hash ->
        f_hash === g_hash
      end)

    case seen_f_before do
      true -> false
      _ -> do_has0(f.(), [f_hash | seen])
    end
  end

  # NOTE: I can't think of an argument as to _why_ this can't terminate, assuming
  # we follow the principle of "corecursive functions terminate once a function call was seen previously"
  # unless it's somehow possible to add an infinite number of distinct functions to the corecursive list.
  @spec sum(nonempty_maybe_improper_list()) :: integer() | no_return()
  def sum(xs) do
    do_sum(xs, 0, [])
  end

  defp do_sum([x | xs], acc, seen) when is_integer(x) do
    do_sum(xs, acc + x, seen)
  end

  defp do_sum([f | _], acc, seen) do
    f_hash = :erlang.phash2(f)

    seen_f_before =
      Enum.any?(seen, fn g_hash ->
        f_hash === g_hash
      end)

    case seen_f_before do
      true -> acc
      _ -> do_sum(f.(), acc, [f_hash | seen])
    end
  end

  @spec fun1(boolean(), boolean()) :: number()
  def fun1(a, _) when a do
    1
  end

  def fun1(_, b) when b do
    -1
  end

  def fun1(_, _) do
    0
  end

  @spec fun2(list({number(), number()}), any()) :: {{:notmatched, number}, {:matched, number}}
  def fun2(xs, target) do
    {notmatched, matched} =
      List.foldl(xs, {0, 0}, fn {x1, x2}, {notmatched, matched} ->
        if x1 == target || x2 == target do
          {notmatched, matched + 1}
        else
          {notmatched + 1, matched}
        end
      end)

    {{:notmatched, notmatched}, {:matched, matched}}
  end

  @spec fun3(list(any()), atom()) :: list({atom(), any()})
  def fun3([], _) do
    []
  end

  def fun3([x | xs], t) do
    [{t, x} | fun3(xs, t)]
  end

  # NOTE: fun4 flattens a list of lists into a single list.
  @spec fun4(list(list(any()))) :: list(any())
  def fun4([]) do
    :error
  end

  def fun4([x]) do
    x
  end

  def fun4([x | [y | ys]]) do
    x ++ fun4([y | ys])
  end
end
