defmodule TimeTracker.ParserTest do
  use ExUnit.Case, async: true

  alias TimeTracker.{Activity, Day, Parser}

  @today ~D[2026-10-17]

  describe "parse_time/1" do
    test "parses a 24-hour hhmm into a Time" do
      assert Parser.parse_time("0915") == {:ok, ~T[09:15:00]}
    end

    test "accepts the first and last minute of the day" do
      assert Parser.parse_time("0000") == {:ok, ~T[00:00:00]}
      assert Parser.parse_time("2359") == {:ok, ~T[23:59:00]}
    end

    for bad <- ["915", "09155", "2400", "1260", "9a15", "+915", " 915", "", "09:15"] do
      @bad bad
      test "rejects #{inspect(bad)}" do
        assert Parser.parse_time(@bad) == {:error, :invalid_time}
      end
    end
  end

  describe "parse_record/1" do
    test "a time followed by a description starts an activity" do
      assert Parser.parse_record("0915 code review") ==
               {:ok, {:start, ~T[09:15:00], "code review"}}
    end

    test "surrounding whitespace is not part of the description" do
      assert Parser.parse_record("0915   code review  ") ==
               {:ok, {:start, ~T[09:15:00], "code review"}}
    end

    test "a time followed by exactly `out` ends the day" do
      assert Parser.parse_record("1730 out") == {:ok, {:out, ~T[17:30:00]}}
    end

    test "a time with no description is an error" do
      assert Parser.parse_record("0915") == {:error, :missing_description}
      assert Parser.parse_record("0915   ") == {:error, :missing_description}
    end

    test "a bad time is an error" do
      assert Parser.parse_record("915 code review") == {:error, :invalid_time}
    end
  end

  describe "parse_header/2" do
    test "a dd-MMM header in the past belongs to the current year" do
      assert Parser.parse_header("# 16-Oct", @today) == {:ok, ~D[2026-10-16]}
    end

    test "today belongs to the current year" do
      assert Parser.parse_header("# 17-Oct", @today) == {:ok, ~D[2026-10-17]}
    end

    test "a date that would be in the future belongs to the previous year" do
      assert Parser.parse_header("# 18-Oct", @today) == {:ok, ~D[2025-10-18]}
      assert Parser.parse_header("# 30-Dec", ~D[2027-01-02]) == {:ok, ~D[2026-12-30]}
    end

    test "a date that doesn't exist in its inferred year is an error" do
      assert Parser.parse_header("# 31-Sep", @today) == {:error, :invalid_date}
      assert Parser.parse_header("# 29-Feb", @today) == {:error, :invalid_date}
      assert Parser.parse_header("# 29-Feb", ~D[2028-03-01]) == {:ok, ~D[2028-02-29]}
    end

    for bad <- ["# 6-Oct", "# 16-Okt", "# 16-oct", "## 16-Oct", "#16-Oct", "# 16 Oct"] do
      @bad bad
      test "rejects #{inspect(bad)}" do
        assert Parser.parse_header(@bad, @today) == {:error, :invalid_header}
      end
    end
  end

  describe "parse/2" do
    test "an empty document has no days" do
      assert Parser.parse("", @today) == {:ok, []}
    end

    test "parses days into activities that end where the next one starts" do
      document = """
      # 14-Oct
      0800 email and planning
      0915 code review

      1200 out

      # 15-Oct
      0830 standup
      1700 out
      """

      assert Parser.parse(document, @today) ==
               {:ok,
                [
                  %Day{
                    date: ~D[2026-10-14],
                    activities: [
                      %Activity{
                        start: ~T[08:00:00],
                        stop: ~T[09:15:00],
                        description: "email and planning"
                      },
                      %Activity{
                        start: ~T[09:15:00],
                        stop: ~T[12:00:00],
                        description: "code review"
                      }
                    ]
                  },
                  %Day{
                    date: ~D[2026-10-15],
                    activities: [
                      %Activity{start: ~T[08:30:00], stop: ~T[17:00:00], description: "standup"}
                    ]
                  }
                ]}
    end

    test "content before the first header is an error" do
      assert Parser.parse("0800 email\n# 14-Oct\n0900 out\n", @today) ==
               {:error, [{1, :content_before_header}]}
    end

    test "a bad line is reported with its line number" do
      assert Parser.parse("# 14-Oct\n0800 email\n9am standup\n1700 out\n", @today) ==
               {:error, [{3, :invalid_time}]}
    end

    test "a day without `out` is reported at its header" do
      assert Parser.parse("# 14-Oct\n0800 email\n", @today) == {:error, [{1, :missing_out}]}
    end

    test "times that don't increase are reported at the later record" do
      assert Parser.parse("# 14-Oct\n0900 email\n0830 standup\n1700 out\n", @today) ==
               {:error, [{3, :time_not_increasing}]}

      assert Parser.parse("# 14-Oct\n0900 email\n0900 standup\n1700 out\n", @today) ==
               {:error, [{3, :time_not_increasing}]}
    end

    test "a record after `out` is an error" do
      assert Parser.parse("# 14-Oct\n0900 email\n1700 out\n1800 more email\n", @today) ==
               {:error, [{4, :record_after_out}]}
    end

    test "the same date twice is reported at the second header" do
      assert Parser.parse("# 14-Oct\n0900 a\n1000 out\n# 14-Oct\n1100 b\n1200 out\n", @today) ==
               {:error, [{4, :duplicate_day}]}
    end

    test "errors from every day are collected in line order" do
      document = """
      # 14-Oct
      0900 email
      # 15-Oct
      9am standup
      1700 out
      # 31-Sep
      0900 email
      1000 out
      """

      assert Parser.parse(document, @today) ==
               {:error, [{1, :missing_out}, {4, :invalid_time}, {6, :invalid_date}]}
    end
  end
end
