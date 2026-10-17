defmodule TimeTrackerTest do
  use ExUnit.Case
  doctest TimeTracker

  test "greets the world" do
    assert TimeTracker.hello() == :world
  end
end
