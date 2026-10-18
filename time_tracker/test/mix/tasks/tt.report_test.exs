defmodule Mix.Tasks.Tt.ReportTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Tt.Report, as: ReportTask

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    {erl_date, _time} = :calendar.local_time()
    %{today: Date.from_erl!(erl_date), path: Path.join(dir, "time.md")}
  end

  test "reports this week's time from a markdown file", %{today: today, path: path} do
    File.write!(path, """
    #{header(today)}
    0900 code review
    1030 pairing
    1200 out
    """)

    output = capture_io(fn -> ReportTask.run([path]) end)

    assert output =~ ~r/code review\s+1:30/
    assert output =~ ~r/pairing\s+1:30/
    assert output =~ ~r/Total\s+3:00/
  end

  test "--from and --to choose the period", %{today: today, path: path} do
    earlier = Date.add(today, -8)

    File.write!(path, """
    #{header(earlier)}
    0900 planning
    0945 out
    #{header(today)}
    0900 code review
    1000 out
    """)

    output =
      capture_io(fn ->
        ReportTask.run([
          path,
          "--from",
          Date.to_iso8601(earlier),
          "--to",
          Date.to_iso8601(earlier)
        ])
      end)

    assert output =~ ~r/planning\s+0:45/
    refute output =~ "code review"
  end

  test "a file with errors fails, listing every error with its line", %{today: today, path: path} do
    File.write!(path, """
    0800 too early
    #{header(today)}
    9am standup
    1700 out
    """)

    error = assert_raise Mix.Error, fn -> ReportTask.run([path]) end

    assert error.message =~ "line 1"
    assert error.message =~ "line 3"
  end

  defp header(date), do: Calendar.strftime(date, "# %d-%b")
end
