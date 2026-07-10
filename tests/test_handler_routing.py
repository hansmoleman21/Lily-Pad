"""lambda_handler routing, auth, and /data tiering tests against moto."""

import base64
import json


def make_event(route_key, body=None, headers=None, b64=False):
    return {
        "routeKey": route_key,
        "headers": headers or {},
        "body": body,
        "isBase64Encoded": b64,
    }


def post_log(h, text=None, key=None, raw_body=None):
    body = raw_body if raw_body is not None else json.dumps({"text": text})
    headers = {"x-api-key": key} if key is not None else {}
    return h.lambda_handler(make_event("POST /log", body=body, headers=headers), None)


class TestLogAuth:
    def test_correct_key_succeeds(self, events_table, api_key):
        resp = post_log(events_table, text="last poop?", key=api_key)
        assert resp["statusCode"] == 200
        assert "poop" in resp["body"]

    def test_wrong_key_rejected(self, events_table, api_key):
        resp = post_log(events_table, text="poop", key="wrong-key")
        assert resp["statusCode"] == 403
        assert events_table.query_last("poop") is None

    def test_missing_key_rejected(self, events_table, api_key):
        resp = post_log(events_table, text="poop")
        assert resp["statusCode"] == 403

    def test_unfetchable_key_fails_closed(self, events_table, monkeypatch):
        # Regression: compare_digest("", "") is True, so an empty configured
        # key plus an empty provided key must still be rejected.
        monkeypatch.setenv("API_KEY_SSM_PATH", "/lily-pad/does-not-exist")
        events_table.get_api_key.cache_clear()
        resp = post_log(events_table, text="poop", key="")
        assert resp["statusCode"] == 403

    def test_unset_ssm_path_fails_closed(self, events_table):
        resp = post_log(events_table, text="poop", key="")
        assert resp["statusCode"] == 403


class TestLogValidation:
    def test_invalid_json_is_400(self, events_table, api_key):
        resp = post_log(events_table, key=api_key, raw_body="not json {")
        assert resp["statusCode"] == 400

    def test_missing_text_is_400(self, events_table, api_key):
        resp = post_log(events_table, key=api_key, raw_body=json.dumps({"other": 1}))
        assert resp["statusCode"] == 400

    def test_over_length_text_is_400(self, events_table, api_key):
        h = events_table
        resp = post_log(h, text="note, " + "x" * (h.MAX_TEXT_LEN + 1), key=api_key)
        assert resp["statusCode"] == 400
        assert "too long" in resp["body"]
        assert h.query_last("note") is None

    def test_base64_body_is_decoded(self, events_table, api_key):
        body = base64.b64encode(json.dumps({"text": "poop"}).encode()).decode()
        event = make_event("POST /log", body=body, headers={"x-api-key": api_key}, b64=True)
        resp = events_table.lambda_handler(event, None)
        assert resp["statusCode"] == 200
        assert events_table.query_last("poop") is not None


class TestDashboardData:
    def _seed(self, h):
        h.record_event("pee", None)
        h.record_event("note", "secret vet note")
        h.record_event("medicine", "1 pill")
        h.record_event("weight", "12.5")

    def _get_data(self, h, token=None):
        headers = {"x-dashboard-token": token} if token is not None else {}
        resp = h.lambda_handler(make_event("GET /data", headers=headers), None)
        assert resp["statusCode"] == 200
        types = {e["event_type"] for e in json.loads(resp["body"])["events"]}
        return resp, types

    def test_valid_token_gets_full_payload(self, events_table, dashboard_token):
        self._seed(events_table)
        _, types = self._get_data(events_table, token=dashboard_token)
        assert {"pee", "note", "medicine", "weight"} <= types

    def test_no_token_gets_public_payload(self, events_table, dashboard_token):
        self._seed(events_table)
        _, types = self._get_data(events_table)
        assert "pee" in types
        assert types.isdisjoint({"note", "medicine", "weight"})

    def test_wrong_token_gets_public_payload(self, events_table, dashboard_token):
        self._seed(events_table)
        _, types = self._get_data(events_table, token="wrong-token")
        assert types.isdisjoint({"note", "medicine", "weight"})

    def test_unconfigured_token_gets_public_payload(self, events_table):
        # No DASHBOARD_TOKEN_SSM_PATH set: even an empty provided token must
        # not unlock the full payload (compare_digest("", "") pitfall).
        self._seed(events_table)
        _, types = self._get_data(events_table, token="")
        assert types.isdisjoint({"note", "medicine", "weight"})

    def test_response_headers(self, events_table, dashboard_token):
        resp, _ = self._get_data(events_table)
        assert resp["headers"]["Cache-Control"] == "private, max-age=60"
        assert resp["headers"]["Vary"] == "x-dashboard-token"
        assert "Access-Control-Allow-Origin" not in resp["headers"]
