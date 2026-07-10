"""Pure phrase-matching tests — no AWS involved."""

from handler import (
    match_change_time,
    match_delete,
    match_medicine,
    match_note,
    match_query,
    match_record,
    match_weight,
    match_walk,
    parse_walk_duration,
)


class TestMatchRecord:
    def test_attribute_phrase_beats_base(self):
        assert match_record("soft poop") == ("poop", "soft")
        assert match_record("she had diarrhea") == ("poop", "diarrhea")

    def test_base_phrase_uses_default_attribute(self):
        assert match_record("poop") == ("poop", "normal")
        assert match_record("Lily pooped") == ("poop", "normal")

    def test_no_default_attribute_yields_none(self):
        assert match_record("vomited") == ("vomit", None)

    def test_vomit_attribute(self):
        assert match_record("vomited bile") == ("vomit", "bile")

    def test_voice_mishear_lily_pad_is_pee(self):
        assert match_record("lily pad") == ("pee", None)

    def test_simple_list_event(self):
        assert match_record("ate off the ground") == ("ate_ground", None)

    def test_case_insensitive(self):
        assert match_record("SOFT POOP") == ("poop", "soft")

    def test_no_match(self):
        assert match_record("hello there") is None


class TestMatchQuery:
    def test_last_query(self):
        assert match_query("last poop?") == ("poop", "last")

    def test_count_query(self):
        assert match_query("how many pees today") == ("pee", "count")

    def test_no_match(self):
        assert match_query("nothing relevant") is None


class TestPrefixMatchers:
    def test_note_extracts_content(self):
        assert match_note("Note, vet visit tomorrow") == "vet visit tomorrow"

    def test_note_empty_content_is_none(self):
        assert match_note("note,") is None
        assert match_note("note,   ") is None

    def test_note_requires_prefix(self):
        assert match_note("this is not a note") is None

    def test_medicine_extracts_content(self):
        assert match_medicine("medicine, 1 pill of Benadryl") == "1 pill of Benadryl"
        assert match_medicine("meds, heartworm chew") == "heartworm chew"

    def test_medicine_empty_is_none(self):
        assert match_medicine("medicine,") is None

    def test_change_time_extracts_time_text(self):
        assert match_change_time("change time, yesterday 5:10 PM") == "yesterday 5:10 PM"

    def test_change_time_no_prefix(self):
        assert match_change_time("yesterday 5:10 PM") is None


class TestWalk:
    def test_minutes(self):
        assert parse_walk_duration("35 minutes") == 35

    def test_hours_and_minutes(self):
        assert parse_walk_duration("one hour 20 minutes") == 80

    def test_compound_word_number(self):
        assert parse_walk_duration("twenty-five min") == 25

    def test_no_numbers(self):
        assert parse_walk_duration("a nice stroll") is None

    def test_match_walk_prefix(self):
        assert match_walk("walk, 35 minutes") == 35
        # "lock," is a known Siri mishear of "walk,"
        assert match_walk("lock, 10 minutes") == 10

    def test_match_walk_requires_prefix(self):
        assert match_walk("went 35 minutes") is None


class TestWeight:
    def test_weight_extracts_number(self):
        assert match_weight("weight, 12.5 lbs") == "12.5"

    def test_wait_mishear(self):
        assert match_weight("wait, 13") == "13"

    def test_weight_without_number(self):
        assert match_weight("weight, heavy") is None


class TestDelete:
    def test_delete_phrases(self):
        assert match_delete("undo") is True
        assert match_delete("delete last entry") is True

    def test_non_delete(self):
        assert match_delete("poop") is False
