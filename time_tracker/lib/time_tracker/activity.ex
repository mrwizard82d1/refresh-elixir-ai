defmodule TimeTracker.Activity do
  @moduledoc """
  Models an activity whose duration is to be remembered.
  """

  @enforce_keys [:start, :stop, :description]
  defstruct @enforce_keys

  def minutes(%__MODULE__{start: start, stop: stop}) do
    Time.diff(stop, start, :minute)
  end
end
