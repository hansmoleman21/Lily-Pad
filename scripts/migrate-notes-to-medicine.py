#!/usr/bin/env python3
"""
Dry-run by default. Pass --execute to apply changes.

Finds all Note events whose attribute contains trazodone, gabapentin, or benadryl
(case-insensitive) and re-records them as Medicine events with the same timestamp
and content. The original Note item is deleted.
"""

import argparse
import boto3
from boto3.dynamodb.conditions import Key

TABLE_NAME = "lily-events"
REGION = "us-west-2"
KEYWORDS = ["trazodone", "gabapentin", "benadryl"]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--execute", action="store_true", help="Apply changes (default is dry-run)")
    args = parser.parse_args()

    dynamodb = boto3.resource("dynamodb", region_name=REGION)
    table = dynamodb.Table(TABLE_NAME)

    resp = table.query(
        KeyConditionExpression=Key("event_type").eq("note")
    )
    notes = resp.get("Items", [])
    while "LastEvaluatedKey" in resp:
        resp = table.query(
            KeyConditionExpression=Key("event_type").eq("note"),
            ExclusiveStartKey=resp["LastEvaluatedKey"]
        )
        notes.extend(resp.get("Items", []))

    matches = [
        n for n in notes
        if any(kw in (n.get("attribute") or "").lower() for kw in KEYWORDS)
    ]

    if not matches:
        print("No matching note events found.")
        return

    print(f"{'DRY RUN — ' if not args.execute else ''}Found {len(matches)} note(s) to migrate:\n")
    for item in matches:
        print(f"  [{item['timestamp']}] {item.get('attribute')}")

    if not args.execute:
        print("\nRun with --execute to apply.")
        return

    print()
    for item in matches:
        ts = item["timestamp"]
        content = item.get("attribute", "")
        table.put_item(Item={"event_type": "medicine", "timestamp": ts, "attribute": content})
        table.delete_item(Key={"event_type": "note", "timestamp": ts})
        print(f"  Migrated [{ts}] → medicine: {content}")

    print(f"\nDone. {len(matches)} note(s) converted to medicine events.")

if __name__ == "__main__":
    main()
