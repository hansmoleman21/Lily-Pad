import os

# Must be set before handler/boto3 imports so no real AWS account is touched.
os.environ.setdefault("AWS_DEFAULT_REGION", "us-west-2")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")
os.environ.setdefault("AWS_SESSION_TOKEN", "testing")
os.environ.setdefault("DYNAMODB_TABLE", "lily-events-test")

import time
from types import SimpleNamespace

import boto3
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from moto import mock_aws

import handler as handler_module


@pytest.fixture
def aws():
    with mock_aws():
        yield


@pytest.fixture
def events_table(aws, monkeypatch):
    """Create the events table in moto and yield the handler module with all
    per-container caches reset."""
    boto3.resource("dynamodb").create_table(
        TableName=os.environ["DYNAMODB_TABLE"],
        KeySchema=[
            {"AttributeName": "event_type", "KeyType": "HASH"},
            {"AttributeName": "timestamp", "KeyType": "RANGE"},
        ],
        AttributeDefinitions=[
            {"AttributeName": "event_type", "AttributeType": "S"},
            {"AttributeName": "timestamp", "AttributeType": "S"},
        ],
        BillingMode="PAY_PER_REQUEST",
    )
    monkeypatch.delenv("API_KEY_SSM_PATH", raising=False)
    handler_module._TABLE = None
    handler_module.get_api_key.cache_clear()
    yield handler_module
    handler_module._TABLE = None
    handler_module.get_api_key.cache_clear()


@pytest.fixture
def api_key(events_table, monkeypatch):
    """Store a shortcuts API key in moto SSM and point the handler at it."""
    key = "test-shortcuts-key"
    boto3.client("ssm").put_parameter(
        Name="/lily-pad/shortcuts-api-key", Value=key, Type="SecureString"
    )
    monkeypatch.setenv("API_KEY_SSM_PATH", "/lily-pad/shortcuts-api-key")
    events_table.get_api_key.cache_clear()
    return key


@pytest.fixture
def okta_token(events_table, monkeypatch):
    """Factory that mints RS256 JWTs shaped like Okta access tokens. The
    handler's JWKS client is stubbed with the matching public key, so no
    network calls are made. Keyword overrides replace/extend the claims."""
    issuer = "https://okta.test"
    client_id = "0oa-test-client"
    monkeypatch.setenv("OKTA_ISSUER", issuer)
    monkeypatch.setenv("OKTA_CLIENT_ID", client_id)

    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    signing_key = SimpleNamespace(key=private_key.public_key())
    stub = SimpleNamespace(get_signing_key_from_jwt=lambda token: signing_key)
    monkeypatch.setattr(events_table, "_jwk_client", lambda: stub)

    def mint(**overrides):
        now = int(time.time())
        claims = {"iss": issuer, "cid": client_id, "iat": now, "exp": now + 3600}
        claims.update(overrides)
        return jwt.encode(claims, private_key, algorithm="RS256")

    return mint
