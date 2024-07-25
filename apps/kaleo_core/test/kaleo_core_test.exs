defmodule KaleoCoreTest do
  use ExUnit.Case
  doctest KaleoCore

  test "greets the world" do
    assert KaleoCore.hello() == :world
  end
end
