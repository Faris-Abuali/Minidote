defmodule Vectorclock do
  def new() do
    %{}
  end

  def eq(vc1, vc2) do
    vc1 === vc2
  end

  def get(vc, p) do
    Map.get(vc, p, 0)
  end

  def increment(vc, p) do
    Map.update(vc, p, 1, fn count -> count + 1 end)
  end

  def leq(vc1, vc2) do
    # need to only look at explicit keys of vc1
    Enum.all?(vc1, fn {key, value1} -> value1 <= get(vc2, key) end)
  end

  def merge(vc1, vc2) do
    Map.merge(vc1, vc2, fn _key, v1, v2 -> max(v1, v2) end)
  end
end
