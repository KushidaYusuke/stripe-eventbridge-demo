import json
import os
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def lambda_handler(event, context):
    # EventBridge wraps the Stripe event in the "detail" field.
    detail = event.get("detail", {})

    stripe_event_id = detail.get("id")
    event_type = detail.get("type")
    object_id = (
        detail.get("data", {})
        .get("object", {})
        .get("id")
    )

    if not stripe_event_id:
        # Nothing to store; surface the malformed event for quick diagnosis.
        raise ValueError(f"Missing Stripe event id in payload: {json.dumps(detail)}")

    item = {
        "event_id": stripe_event_id,
        "event_type": event_type or "unknown",
        "object_id": object_id or "n/a",
        "raw_payload": json.dumps(detail),
        "received_at": event.get("time"),
    }

    try:
        # PutItem with conditional write to avoid duplicating the same event id.
        table.put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(event_id)",
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] != "ConditionalCheckFailedException":
            # Re-raise unexpected errors so EventBridge can retry.
            raise
        # Duplicate event id; treat as idempotent success.
    return {"status": "ok", "event_id": stripe_event_id}
