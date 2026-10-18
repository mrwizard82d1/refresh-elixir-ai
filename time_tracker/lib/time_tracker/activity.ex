defmodule TimeTracker.Activity do
  @enforce_keys [:start, :stop, :description]
  defstruct @enforce_keys

  def minutes(activity) do
    165
  end

  def description(activity) do
    "foo"
  end
end

