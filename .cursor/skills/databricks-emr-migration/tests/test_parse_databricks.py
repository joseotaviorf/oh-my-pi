import json
import sys
import unittest
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR))

from databricks_client import parse_command_result


FIXTURES = Path(__file__).parent / "fixtures"


class ParseDatabricksTests(unittest.TestCase):
    def test_parse_table_count(self) -> None:
        payload = json.loads((FIXTURES / "table_count.json").read_text())
        parsed = parse_command_result(payload)
        self.assertEqual(parsed.columns, ["cnt"])
        self.assertEqual(parsed.row_dicts[0]["cnt"], "1204431")

    def test_parse_table_sample(self) -> None:
        payload = json.loads((FIXTURES / "table_sample.json").read_text())
        parsed = parse_command_result(payload)
        self.assertEqual(parsed.columns, ["sk_offer", "sk_client"])
        self.assertEqual(len(parsed.row_dicts), 2)
        self.assertEqual(parsed.row_dicts[0]["sk_offer"], "101")

    def test_parse_describe_text(self) -> None:
        payload = json.loads((FIXTURES / "describe_text.json").read_text())
        parsed = parse_command_result(payload)
        self.assertEqual(len(parsed.row_dicts), 2)
        self.assertEqual(parsed.row_dicts[0]["col_name"], "sk_offer")


if __name__ == "__main__":
    unittest.main()
