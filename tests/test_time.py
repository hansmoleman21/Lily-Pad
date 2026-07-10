"""Time parsing/formatting tests — no AWS involved."""

from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from handler import format_time, parse_pacific_datetime, time_since

PACIFIC = ZoneInfo("America/Los_Angeles")


def _expected_utc_iso(pacific_dt: datetime) -> str:
    return pacific_dt.astimezone(timezone.utc).isoformat(timespec="seconds")


class TestParsePacificDatetime:
    def test_yesterday(self):
        expected_date = (datetime.now(PACIFIC) - timedelta(days=1)).date()
        expected = _expected_utc_iso(
            datetime(expected_date.year, expected_date.month, expected_date.day,
                     17, 10, tzinfo=PACIFIC)
        )
        assert parse_pacific_datetime("yesterday 5:10 PM") == expected

    def test_today(self):
        d = datetime.now(PACIFIC).date()
        expected = _expected_utc_iso(datetime(d.year, d.month, d.day, 7, 5, tzinfo=PACIFIC))
        assert parse_pacific_datetime("today 7:05 AM") == expected

    def test_midnight_is_hour_zero(self):
        d = datetime.now(PACIFIC).date()
        expected = _expected_utc_iso(datetime(d.year, d.month, d.day, 0, 0, tzinfo=PACIFIC))
        assert parse_pacific_datetime("today 12:00 AM") == expected

    def test_noon_is_hour_twelve(self):
        d = datetime.now(PACIFIC).date()
        expected = _expected_utc_iso(datetime(d.year, d.month, d.day, 12, 30, tzinfo=PACIFIC))
        assert parse_pacific_datetime("today 12:30 PM") == expected

    def test_full_month_name(self):
        year = datetime.now(PACIFIC).year
        expected = _expected_utc_iso(datetime(year, 3, 3, 16, 15, tzinfo=PACIFIC))
        assert parse_pacific_datetime("March 3 4:15 PM") == expected

    def test_abbreviated_month_name(self):
        year = datetime.now(PACIFIC).year
        expected = _expected_utc_iso(datetime(year, 3, 3, 16, 15, tzinfo=PACIFIC))
        assert parse_pacific_datetime("Mar 3 4:15 PM") == expected

    def test_dst_winter_offset(self):
        # January is PST (-08:00): 9:30 AM Pacific == 17:30 UTC
        year = datetime.now(PACIFIC).year
        result = parse_pacific_datetime("January 15 9:30 AM")
        assert result == datetime(year, 1, 15, 17, 30, tzinfo=timezone.utc).isoformat(
            timespec="seconds"
        )

    def test_dst_summer_offset(self):
        # July is PDT (-07:00): 9:30 AM Pacific == 16:30 UTC
        year = datetime.now(PACIFIC).year
        result = parse_pacific_datetime("July 15 9:30 AM")
        assert result == datetime(year, 7, 15, 16, 30, tzinfo=timezone.utc).isoformat(
            timespec="seconds"
        )

    def test_garbage_returns_none(self):
        assert parse_pacific_datetime("gibberish") is None

    def test_invalid_day_returns_none(self):
        assert parse_pacific_datetime("February 30 1:00 PM") is None

    def test_missing_time_returns_none(self):
        assert parse_pacific_datetime("yesterday") is None


class TestTimeSince:
    def _iso_ago(self, **kwargs) -> str:
        dt = datetime.now(timezone.utc) - timedelta(**kwargs)
        return dt.isoformat(timespec="seconds")

    def test_minutes_only(self):
        assert time_since(self._iso_ago(minutes=45)) == "45 minutes ago"

    def test_singular_minute(self):
        assert time_since(self._iso_ago(minutes=1)) == "1 minute ago"

    def test_hours_and_minutes(self):
        assert time_since(self._iso_ago(hours=1, minutes=20)) == "1 hour 20 minutes ago"

    def test_days_and_hours(self):
        assert time_since(self._iso_ago(days=2, hours=3)) == "2 days 3 hours ago"


class TestFormatTime:
    def test_today(self):
        iso = datetime.now(timezone.utc).isoformat(timespec="seconds")
        assert format_time(iso).startswith("today at ")

    def test_yesterday(self):
        iso = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat(timespec="seconds")
        # A timestamp exactly 24h ago is "yesterday" unless we're within a DST
        # shift window; the prefix check keeps this deterministic enough.
        assert format_time(iso).startswith(("yesterday at ", "today at "))

    def test_older_date_uses_month_day(self):
        dt = datetime.now(timezone.utc) - timedelta(days=10)
        formatted = format_time(dt.isoformat(timespec="seconds"))
        local = dt.astimezone(PACIFIC)
        assert formatted.startswith(local.strftime("%b %-d at "))
