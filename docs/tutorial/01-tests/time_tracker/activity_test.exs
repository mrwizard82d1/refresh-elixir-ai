defmodule TimeTracker.ActivityTest do
  use ExUnit.Case, async: true

  alias TimeTracker.Activity

  test "minutes/1 is the time from start to stop" do
    activity = %Activity{start: ~T[09:15:00], stop: ~T[12:00:00], description: "code review"}

    assert Activity.minutes(activity) == 165
  end

  test "every field is required" do
    assert_raise ArgumentError, fn -> struct!(Activity, description: "code review") end
  end
end
