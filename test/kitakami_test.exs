defmodule KitakamiTest do
  use ExUnit.Case
  doctest Kitakami

  test "greets the world" do
    assert Kitakami.hello() == :world
  end
end
