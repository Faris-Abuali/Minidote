defmodule Vectorclock do
  @opaque t :: %{optional(pid()) => non_neg_integer()}

  @spec new() :: Vectorclock.t()
  def new() do
    %{}
  end

  @spec eq(Vectorclock.t(), Vectorclock.t()) :: boolean()
  def eq(vc1, vc2) do
    vc1 === vc2
  end

  @spec get(Vectorclock.t(), pid()) :: non_neg_integer()
  def get(vc, p) do
    Map.get(vc, p, 0)
  end

  @spec increment(Vectorclock.t(), pid()) :: Vectorclock.t()
  def increment(vc, p) do
    Map.update(vc, p, 1, fn count -> count + 1 end)
  end

  @spec leq(Vectorclock.t(), Vectorclock.t()) :: boolean()
  def leq(vc1, vc2) do
    # need to only look at explicit keys of vc1
    Enum.all?(vc1, fn {key, value1} -> value1 <= get(vc2, key) end)
  end

  @spec merge(Vectorclock.t(), Vectorclock.t()) :: Vectorclock.t()
  def merge(vc1, vc2) do
    Map.merge(vc1, vc2, fn _key, v1, v2 -> max(v1, v2) end)
  end
end
