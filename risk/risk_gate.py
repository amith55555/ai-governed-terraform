#!/usr/bin/env python3
"""Risk gate: classify a Terraform plan JSON as low, medium or high risk.

The level is decided only by the fixed rules below. No AI decides it.
Usage: python3 risk/risk_gate.py PLAN_JSON > risk.json
Output: JSON with "level" and "reasons". Reasons contain resource addresses only.
"""
import json
import sys

LEVELS = ["low", "medium", "high"]

# Resources that hold data: losing them loses data.
STATEFUL_TYPES = {"aws_dynamodb_table", "aws_s3_bucket"}

# Resources that grant permissions.
PERMISSION_TYPES = {"aws_s3_bucket_policy", "aws_lambda_permission"}
PERMISSION_PREFIX = "aws_iam_"


def reason(level, address, rule, detail):
    return {"level": level, "address": address, "rule": rule, "detail": detail}


def classify(plan):
    reasons = []
    for rc in plan.get("resource_changes", []):
        if rc.get("mode") != "managed":
            continue
        actions = rc["change"]["actions"]
        if actions == ["no-op"]:
            continue

        address = rc["address"]
        rtype = rc["type"]
        before = rc["change"].get("before") or {}
        after = rc["change"].get("after") or {}

        if rtype in STATEFUL_TYPES:
            if "delete" in actions and "create" in actions:
                reasons.append(reason("high", address, "stateful-replace",
                                      "replace deletes the existing data"))
            elif "delete" in actions:
                reasons.append(reason("high", address, "stateful-destroy",
                                      "destroy deletes the data"))
            elif "forget" in actions:
                reasons.append(reason("high", address, "stateful-forget",
                                      "removed from Terraform; data no longer managed"))

            if (rtype == "aws_dynamodb_table"
                    and before.get("deletion_protection_enabled") is True
                    and after.get("deletion_protection_enabled") is False):
                reasons.append(reason("high", address, "protection-removed",
                                      "deletion protection turned off"))

            if (rtype == "aws_s3_bucket"
                    and before.get("force_destroy") is False
                    and after.get("force_destroy") is True):
                reasons.append(reason("high", address, "force-destroy-enabled",
                                      "force_destroy turned on"))

        if rtype.startswith(PERMISSION_PREFIX) or rtype in PERMISSION_TYPES:
            reasons.append(reason("medium", address, "permissions-change",
                                  "/".join(actions) + " of a permissions resource"))

    level = max((r["level"] for r in reasons), key=LEVELS.index, default="low")
    return {"level": level, "reasons": reasons}


def main(argv):
    if len(argv) != 2:
        print("usage: risk_gate.py PLAN_JSON", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        plan = json.load(f)
    result = classify(plan)
    json.dump(result, sys.stdout, indent=2)
    print()
    print(f"risk level: {result['level']} ({len(result['reasons'])} reasons)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
