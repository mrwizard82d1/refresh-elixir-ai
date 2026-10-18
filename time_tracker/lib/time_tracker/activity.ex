defmodule TimeTracker.Activity do
  @enforce_keys [:start, :stop, :description]
  defstruct @enforce_keys

  def minutes(activity) do
    # The function, `Time.diff`, calculates the difference
    # between two time points in seconds. I assume
    # the microsecands portion of the `Time` struct
    # results in a floating point number.
    (Time.diff(activity.stop, activity.start)) / 60
  end

  def description(activity) do
    "foo"
  end
end

