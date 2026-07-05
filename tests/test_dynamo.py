"""DynamoDB helper and handle_message tests against moto."""

from datetime import datetime, timedelta, timezone

from boto3.dynamodb.conditions import Key


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat(timespec="seconds")


def _put(h, event_type, minutes_ago, attribute=None):
    item = {
        "event_type": event_type,
        "timestamp": _iso(datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)),
    }
    if attribute is not None:
        item["attribute"] = attribute
    h._table().put_item(Item=item)
    return item


class TestRecordEvent:
    def test_writes_item_with_attribute(self, events_table):
        h = events_table
        ts = h.record_event("poop", "soft")
        item = h.query_last("poop")
        assert item == {"event_type": "poop", "timestamp": ts, "attribute": "soft"}

    def test_writes_item_without_attribute(self, events_table):
        h = events_table
        ts = h.record_event("pee", None)
        item = h.query_last("pee")
        assert item == {"event_type": "pee", "timestamp": ts}
        assert "attribute" not in item


class TestQueryLast:
    def test_returns_most_recent(self, events_table):
        h = events_table
        _put(h, "pee", minutes_ago=60)
        newest = _put(h, "pee", minutes_ago=5)
        assert h.query_last("pee") == newest

    def test_empty_returns_none(self, events_table):
        assert events_table.query_last("pee") is None


class TestFindLatestEvent:
    def test_across_types(self, events_table):
        h = events_table
        _put(h, "pee", minutes_ago=30)
        newest = _put(h, "walk", minutes_ago=10, attribute="25")
        _put(h, "poop", minutes_ago=20, attribute="normal")
        assert h.find_latest_event() == newest

    def test_empty_returns_none(self, events_table):
        assert events_table.find_latest_event() is None


class TestDeleteLastEvent:
    def test_deletes_newest_across_types(self, events_table):
        h = events_table
        older = _put(h, "pee", minutes_ago=30)
        newest = _put(h, "poop", minutes_ago=5, attribute="normal")
        deleted = h.delete_last_event()
        assert deleted == newest
        assert h.query_last("poop") is None
        assert h.query_last("pee") == older

    def test_empty_returns_none(self, events_table):
        assert events_table.delete_last_event() is None


class TestChangeLastEventTime:
    def test_moves_timestamp_and_preserves_attribute(self, events_table):
        h = events_table
        _put(h, "walk", minutes_ago=10, attribute="35")
        new_ts = _iso(datetime.now(timezone.utc) - timedelta(hours=3))
        updated = h.change_last_event_time(new_ts)
        assert updated["timestamp"] == new_ts
        assert updated["attribute"] == "35"
        stored = h.query_last("walk")
        assert stored == {"event_type": "walk", "timestamp": new_ts, "attribute": "35"}


class TestQueryCountToday:
    def test_respects_pacific_midnight_cutoff(self, events_table):
        h = events_table
        _put(h, "pee", minutes_ago=5)
        # 3 days ago is safely before today's Pacific midnight
        _put(h, "pee", minutes_ago=3 * 24 * 60)
        assert h.query_count_today("pee") == 1


class TestQueryAllPages:
    def test_follows_last_evaluated_key(self, events_table, monkeypatch):
        h = events_table

        class PagedTable:
            def __init__(self):
                self.calls = 0

            def query(self, **kwargs):
                self.calls += 1
                if "ExclusiveStartKey" not in kwargs:
                    return {"Items": [{"page": 1}], "LastEvaluatedKey": {"k": "1"}}
                assert kwargs["ExclusiveStartKey"] == {"k": "1"}
                return {"Items": [{"page": 2}]}

        stub = PagedTable()
        monkeypatch.setattr(h, "_TABLE", stub)
        items = h._query_all_pages(Key("event_type").eq("pee"))
        assert items == [{"page": 1}, {"page": 2}]
        assert stub.calls == 2


class TestHandleMessage:
    def test_record_poop(self, events_table):
        h = events_table
        reply = h.handle_message("poop")
        assert reply.startswith("Recorded: Lily pooped (normal)")
        assert h.query_last("poop") is not None

    def test_query_does_not_record(self, events_table):
        h = events_table
        reply = h.handle_message("last poop?")
        assert reply == "No record of Lily having pooped yet."
        assert h.query_last("poop") is None

    def test_undo_deletes(self, events_table):
        h = events_table
        h.handle_message("poop")
        reply = h.handle_message("undo")
        assert reply.startswith("Deleted: Lily pooped (normal)")
        assert h.query_last("poop") is None

    def test_unknown_text_returns_help(self, events_table):
        reply = events_table.handle_message("xyzzy")
        assert reply.startswith("Didn't catch that")
