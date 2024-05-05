defmodule WarmupTest do
  use ExUnit.Case
  doctest Warmup

  test "minimum test" do
    assert Warmup.minimum(3, 7) == 3
    assert Warmup.minimum(5, 4) == 4
  end

  test "swap test" do
    assert Warmup.swap({100, :ok}) == {:ok, 100}
    assert Warmup.swap({100, 200, :ok}) == {:ok, 200, 100}
  end

  test "onlyints test" do
    assert Warmup.only_integers?([4, 7, 2]) == true
    assert Warmup.only_integers?([2, 4, 5.0, 7]) == false
  end

  test "positive test" do
    assert [6, 3, 0] == Warmup.positive([6, -5, 3, 0, -2])
  end

  test "all positive test" do
    assert true == Warmup.all_positive?([1, 2, 3])
    assert false == Warmup.all_positive?([1, -2, 3])
  end

  test "values test" do
    assert [5, 7, 3, 1] == Warmup.values([{:c, 5}, {:z, 7}, {:d, 3}, {:a, 1}])
  end

  test "list minimum test" do
    assert 2 == Warmup.list_min([7, 2, 9])
  end

  test "only integers test true" do
    assert Warmup.only_integers?([4, 7, 5, 2])
  end

  test "only integers test false" do
    assert not Warmup.only_integers?([4, 7, 5.0, 2])
  end

  test "delete test ok" do
    assert {:ok, [{:c, 5}, {:z, 7}, {:a, 1}]} ==
             Warmup.delete(:d, [{:c, 5}, {:z, 7}, {:d, 3}, {:a, 1}])
  end

  test "delete test noop" do
    assert :noop ==
             Warmup.delete(:x, [{:c, 5}, {:z, 7}, {:d, 3}, {:a, 1}])
  end

  test "same test true" do
    assert Warmup.same?({:ok, 2}, {:ok, 2})
  end

  test "same test false" do
    assert not Warmup.same?({:ok, 2}, {:ok, {}})
  end

  defmodule Rec do
    def l0() do [1, &Rec.l0/0] end
    def l1() do [1, 2, &Rec.l2/0] end
    def l2() do [3, 0, &Rec.l1/0] end
  end

  test "has0" do
    assert not Warmup.has0(Rec.l0())
    assert Warmup.has0(Rec.l1())
    assert Warmup.has0(Rec.l2())
    assert Warmup.has0(&Warmup.alternating_list/0)
    assert not Warmup.has0(&Warmup.one_two_l2/0)
    assert not Warmup.has0(&Warmup.one_neg_one_l2/0)
  end

  test "sum of corecursive lists" do
    assert Warmup.sum(&Rec.l0/0) === 1
    assert Warmup.sum(&Rec.l1/0) === 6
    assert Warmup.sum(&Warmup.alternating_list/0) === 0
    assert Warmup.sum(&Warmup.one_two_l2/0) === 3
    assert Warmup.sum(&Warmup.one_neg_one_l2/0) === 0
  end
end
