defmodule TimeTracker.ReportTest do
  use ExUnit.Case, async: true

  alias TimeTracker.{Activity, Day, Report}

  describe "week_of/1" do
    for date <- [~D[2026-10-11], ~D[2026-10-16], ~D[2026-10-17]] do
      @date date
      test "the week containing #{date} runs Sunday to Saturday" do
        assert Report.week_of(@date) == Date.range(~D[2026-10-11], ~D[2026-10-17])
      end
    end
  end

  describe "summarize/2" do
    setup do
      days = [
        day(~D[2026-10-10], [{~T[09:00:00], ~T[10:00:00], "code review"}]),
        day(~D[2026-10-12], [
          {~T[09:00:00], ~T[10:30:00], "code review"},
          {~T[10:30:00], ~T[12:00:00], "pairing"}
        ]),
        day(~D[2026-10-13], [{~T[13:00:00], ~T[13:45:00], "code review"}])
      ]

      %{days: days, week: Date.range(~D[2026-10-11], ~D[2026-10-17])}
    end

    test "totals each description across days in the period", %{days: days, week: week} do
      assert Report.summarize(days, week).by_description == %{
               "code review" => 135,
               "pairing" => 90
             }
    end

    test "totals each day in the period", %{days: days, week: week} do
      assert Report.summarize(days, week).by_day == %{~D[2026-10-12] => 180, ~D[2026-10-13] => 45}
    end

    test "totals the whole period", %{days: days, week: week} do
      assert Report.summarize(days, week).total == 225
    end

    test "keeps the period it summarized", %{days: days, week: week} do
      assert Report.summarize(days, week).period == week
    end

    test "a period with no days is all zeros", %{days: days} do
      report = Report.summarize(days, Date.range(~D[2026-11-01], ~D[2026-11-07]))

      assert {report.by_description, report.by_day, report.total} == {%{}, %{}, 0}
    end
  end

  describe "format_minutes/1" do
    for {minutes, text} <- [{0, "0:00"}, {5, "0:05"}, {65, "1:05"}, {600, "10:00"}] do
      @minutes minutes
      @text text
      test "#{minutes} minutes is #{text}" do
        assert Report.format_minutes(@minutes) == @text
      end
    end
  end

  describe "format/1" do
    test "renders descriptions alphabetically and days in date order" do
      report = %Report{
        period: Date.range(~D[2026-10-11], ~D[2026-10-17]),
        by_description: %{"pairing" => 90, "code review" => 135},
        by_day: %{~D[2026-10-13] => 45, ~D[2026-10-12] => 180},
        total: 225
      }

      assert Report.format(report) == """
             2026-10-11 to 2026-10-17

             By description
               code review       2:15
               pairing           1:30

             By day
               Mon 2026-10-12    3:00
               Tue 2026-10-13    0:45

             Total               3:45
             """
    end
  end

  defp day(date, activities) do
    %Day{
      date: date,
      activities:
        for {start, stop, description} <- activities do
          %Activity{start: start, stop: stop, description: description}
        end
    }
  end
end
