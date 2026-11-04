"""Tests for risk_gate.py: one passing and failing fixture per rule."""
import json
import unittest

from risk_gate import classify


def change(rtype, address, actions, before=None, after=None, mode="managed"):
    return {
        "address": address,
        "mode": mode,
        "type": rtype,
        "change": {"actions": actions, "before": before, "after": after},
    }


def plan(*changes):
    return {"resource_changes": list(changes)}


def rules(result):
    return sorted(r["rule"] for r in result["reasons"])


TABLE = "module.table.aws_dynamodb_table.this"
BUCKET = "module.bucket.aws_s3_bucket.this"


class LowRisk(unittest.TestCase):
    def test_no_changes_is_low(self):
        result = classify(plan(change("aws_dynamodb_table", TABLE, ["no-op"])))
        self.assertEqual(result["level"], "low")
        self.assertEqual(result["reasons"], [])
        self.assertEqual(result["changes"], [])
        self.assertEqual(sum(result["counts"].values()), 0)

    def test_new_bucket_is_low(self):
        result = classify(plan(change("aws_s3_bucket", BUCKET, ["create"], None, {"force_destroy": False})))
        self.assertEqual(result["level"], "low")

    def test_tag_update_on_table_is_low(self):
        result = classify(plan(change("aws_dynamodb_table", TABLE, ["update"],
                                      {"deletion_protection_enabled": True, "tags": {}},
                                      {"deletion_protection_enabled": True, "tags": {"Owner": "amit"}})))
        self.assertEqual(result["level"], "low")

    def test_data_source_is_ignored(self):
        result = classify(plan(change("aws_iam_policy_document", "data.aws_iam_policy_document.x", ["read"], mode="data")))
        self.assertEqual(result["level"], "low")


class HighRisk(unittest.TestCase):
    def test_destroy_table_is_high(self):
        result = classify(plan(change("aws_dynamodb_table", TABLE, ["delete"], {"deletion_protection_enabled": False}, None)))
        self.assertEqual(result["level"], "high")
        self.assertEqual(rules(result), ["stateful-destroy"])

    def test_replace_bucket_is_high(self):
        result = classify(plan(change("aws_s3_bucket", BUCKET, ["delete", "create"], {"force_destroy": False}, {"force_destroy": False})))
        self.assertEqual(rules(result), ["stateful-replace"])

    def test_create_before_destroy_replace_is_high(self):
        result = classify(plan(change("aws_dynamodb_table", TABLE, ["create", "delete"], {}, {})))
        self.assertEqual(rules(result), ["stateful-replace"])

    def test_forget_table_is_high(self):
        result = classify(plan(change("aws_dynamodb_table", TABLE, ["forget"], {}, None)))
        self.assertEqual(rules(result), ["stateful-forget"])

    def test_deletion_protection_off_is_high(self):
        result = classify(plan(change("aws_dynamodb_table", TABLE, ["update"],
                                      {"deletion_protection_enabled": True},
                                      {"deletion_protection_enabled": False})))
        self.assertEqual(rules(result), ["protection-removed"])

    def test_force_destroy_on_is_high(self):
        result = classify(plan(change("aws_s3_bucket", BUCKET, ["update"], {"force_destroy": False}, {"force_destroy": True})))
        self.assertEqual(rules(result), ["force-destroy-enabled"])


class MediumRisk(unittest.TestCase):
    def test_iam_policy_update_is_medium(self):
        result = classify(plan(change("aws_iam_role_policy", "module.lambda.aws_iam_role_policy.this", ["update"], {}, {})))
        self.assertEqual(result["level"], "medium")
        self.assertEqual(rules(result), ["permissions-change"])

    def test_lambda_permission_create_is_medium(self):
        result = classify(plan(change("aws_lambda_permission", "module.api.aws_lambda_permission.api", ["create"], None, {})))
        self.assertEqual(result["level"], "medium")

    def test_highest_level_wins(self):
        result = classify(plan(
            change("aws_iam_role_policy", "module.lambda.aws_iam_role_policy.this", ["update"], {}, {}),
            change("aws_dynamodb_table", TABLE, ["delete"], {}, None),
        ))
        self.assertEqual(result["level"], "high")
        self.assertEqual(rules(result), ["permissions-change", "stateful-destroy"])

class Summary(unittest.TestCase):
    """counts and changes are for tf-check; they must never change the level."""

    def test_each_action_has_the_right_kind(self):
        cases = [
            (["create"], "add"),
            (["update"], "change"),
            (["delete"], "destroy"),
            (["delete", "create"], "replace"),
            (["create", "delete"], "replace"),
            (["forget"], "forget"),
            (["create", "forget"], "forget"),
            (["something-new"], "other"),
        ]
        for actions, kind in cases:
            with self.subTest(actions=actions):
                result = classify(plan(change("aws_sns_topic", "aws_sns_topic.x", actions, {}, {})))
                self.assertEqual(result["changes"], [{"address": "aws_sns_topic.x", "action": kind}])
                self.assertEqual(result["counts"][kind], 1)
                self.assertEqual(sum(result["counts"].values()), 1)

    def test_no_op_and_data_sources_are_not_counted(self):
        result = classify(plan(
            change("aws_sns_topic", "aws_sns_topic.x", ["no-op"]),
            change("aws_iam_policy_document", "data.aws_iam_policy_document.x", ["read"], mode="data"),
        ))
        self.assertEqual(result["changes"], [])
        self.assertEqual(sum(result["counts"].values()), 0)

    def test_many_harmless_changes_stay_low(self):
        changes = [change("aws_sns_topic", f"aws_sns_topic.t{i}", ["create"], None, {}) for i in range(50)]
        result = classify(plan(*changes))
        self.assertEqual(result["level"], "low")
        self.assertEqual(result["counts"]["add"], 50)

    def test_summary_never_contains_attribute_values(self):
        result = classify(plan(change("aws_iam_role", "aws_iam_role.x", ["update"],
                                      {"description": "before-value"},
                                      {"description": "after-value"})))
        text = json.dumps(result)
        self.assertNotIn("before-value", text)
        self.assertNotIn("after-value", text)

if __name__ == "__main__":
    unittest.main()
