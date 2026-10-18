defmodule TimeTracker.Activity do
  @enforce_keys [:start, :stop, :description]
  defstruct @enforce_keys

  def minutes(activity) do
    Time.diff(activity.stop, activity.start, :minute)
  end

  def description(activity) do
    "foo"
  end
end

