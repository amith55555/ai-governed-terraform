"""Items API: the Lambda function behind the HTTP API.

Routes:
  GET  /health       -> {"status": "ok"}
  POST /items        -> create an item from {"name": "..."}
  GET  /items        -> list up to 50 items
  GET  /items/{id}   -> get one item
"""

import base64
import json
import logging
import os
import uuid
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel("INFO")

# Created once when Lambda starts a container, then reused for every request.
# TABLE_NAME and BUCKET_NAME are set by Terraform (lambda_function module).
TABLE = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
S3 = boto3.client("s3")
BUCKET = os.environ["BUCKET_NAME"]

MAX_NAME_LENGTH = 100
MAX_ID_LENGTH = 64
LIST_LIMIT = 50


def response(status, body):
    """Build the reply in the format API Gateway expects."""
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str),
    }


def parse_body(event):
    """Return the request body as a dict, or None if missing or not a JSON object."""
    body = event.get("body") or ""
    if event.get("isBase64Encoded"):
        try:
            body = base64.b64decode(body).decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            return None
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def health(event):
    return response(200, {"status": "ok", "service": "items-api"})


def create_item(event):
    data = parse_body(event)
    if data is None:
        return response(400, {"error": "body must be a JSON object"})

    name = data.get("name")
    if not isinstance(name, str) or not name.strip():
        return response(400, {"error": "'name' must be a non-empty string"})
    name = name.strip()
    if len(name) > MAX_NAME_LENGTH:
        return response(400, {"error": f"'name' must be at most {MAX_NAME_LENGTH} characters"})

    item = {
        "id": str(uuid.uuid4()),
        "name": name,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    TABLE.put_item(Item=item)
    S3.put_object(
        Bucket=BUCKET,
        Key=f"items/{item['id']}.json",
        Body=json.dumps(item),
        ContentType="application/json",
    )
    logger.info("created item %s", item["id"])
    return response(201, item)


def get_item(event):
    item_id = (event.get("pathParameters") or {}).get("id")
    if not item_id or len(item_id) > MAX_ID_LENGTH:
        return response(404, {"error": "item not found"})
    item = TABLE.get_item(Key={"id": item_id}).get("Item")
    if item is None:
        return response(404, {"error": "item not found"})
    return response(200, item)


def list_items(event):
    result = TABLE.scan(Limit=LIST_LIMIT)
    return response(200, {"items": result.get("Items", [])})


ROUTES = {
    "GET /health": health,
    "POST /items": create_item,
    "GET /items": list_items,
    "GET /items/{id}": get_item,
}


def handler(event, context):
    """Entry point: Lambda calls this for every request."""
    route = ROUTES.get(event.get("routeKey"))
    if route is None:
        return response(404, {"error": "not found"})
    try:
        return route(event)
    except Exception:
        # Full error goes to CloudWatch Logs; the caller only sees a generic message.
        logger.exception("unhandled error on %s", event.get("routeKey"))
        return response(500, {"error": "internal error"})
