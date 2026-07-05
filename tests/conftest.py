import os

# Must be set before handler/boto3 imports so no real AWS account is touched.
os.environ.setdefault("AWS_DEFAULT_REGION", "us-west-2")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")
os.environ.setdefault("AWS_SESSION_TOKEN", "testing")
os.environ.setdefault("DYNAMODB_TABLE", "lily-events-test")

import boto3
import pytest
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
    monkeypatch.delenv("DASHBOARD_TOKEN_SSM_PATH", raising=False)
    handler_module._TABLE = None
    handler_module.get_api_key.cache_clear()
    handler_module.get_dashboard_token.cache_clear()
    yield handler_module
    handler_module._TABLE = None
    handler_module.get_api_key.cache_clear()
    handler_module.get_dashboard_token.cache_clear()


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
def dashboard_token(events_table, monkeypatch):
    """Store a dashboard token in moto SSM and point the handler at it."""
    token = "test-dashboard-token"
    boto3.client("ssm").put_parameter(
        Name="/lily-pad/dashboard-token", Value=token, Type="SecureString"
    )
    monkeypatch.setenv("DASHBOARD_TOKEN_SSM_PATH", "/lily-pad/dashboard-token")
    events_table.get_dashboard_token.cache_clear()
    return token
