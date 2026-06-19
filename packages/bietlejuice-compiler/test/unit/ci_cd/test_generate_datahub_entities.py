"""Unit tests for the DataHub entity generate script's pure helpers.

Covers the three behaviors that protect the manual audit from CI regressions:
  * description extraction (full MD body minus assets/glossary/golden-query sections)
  * deterministic per-query stable URNs (index 0 == legacy value)
  * multi-golden-query stable-URN enforcement over both YAML forms
  * description injection that survives a YAML round-trip without mangling SQL blocks
"""

import tempfile
import unittest
import uuid
from pathlib import Path

import yaml

from scripts.ci_cd import generate_and_push_datahub_entities as g

_NS = uuid.UUID("a1b2c3d4-e5f6-7890-abcd-ef1234567890")

_SAMPLE_MD = """# Widgets

## Overview

Widgets are the core entity. Critical: always filter status = 'ACTIVE'.

## Key Metrics

- conversion_rate = signed / total

## Dos and Don'ts

- DO use sk_widget for counting.



- DON'T mix grains.

## Relationships with Other Entities

JOIN dw_widget.fact_widget ON sk_widget.

## Tables

| table | grain |
|---|---|
| `dw_widget.fact_widget` | 1 row per widget |

## Glossary and Synonyms

- **Widget** → the thing.

## Golden Queries

### Query 1 — count

```sql
SELECT count(*) FROM dw_widget.fact_widget
```

## DataHub catalog

- Data Product: urn:li:dataProduct:widgets
"""


class ExtractDescriptionTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.NamedTemporaryFile(
            mode="w", suffix=".md", delete=False, encoding="utf-8"
        )
        self._tmp.write(_SAMPLE_MD)
        self._tmp.close()
        self.md_path = Path(self._tmp.name)
        self.desc = g._extract_description_from_md(self.md_path)

    def tearDown(self) -> None:
        self.md_path.unlink(missing_ok=True)

    def test_keeps_narrative_sections(self) -> None:
        for keep in (
            "## Overview",
            "## Key Metrics",
            "## Dos and Don'ts",
            "## Relationships with Other Entities",
            "sk_widget",
        ):
            self.assertIn(keep, self.desc)

    def test_excludes_asset_glossary_gq_sections(self) -> None:
        for drop in (
            "## Tables",
            "## Glossary and Synonyms",
            "## Golden Queries",
            "## DataHub catalog",
            "SELECT count(*)",
            "the thing.",
        ):
            self.assertNotIn(drop, self.desc)

    def test_collapses_excess_blank_lines(self) -> None:
        self.assertNotIn("\n\n\n", self.desc)


class StableUrnTest(unittest.TestCase):
    def test_index_zero_matches_legacy(self) -> None:
        self.assertEqual(
            g._stable_urn_for_query("payments", 0),
            f"urn:li:query:{uuid.uuid5(_NS, 'payments')}",
        )

    def test_higher_indices_distinct_and_deterministic(self) -> None:
        first = g._stable_urn_for_query("payments", 1)
        self.assertEqual(first, f"urn:li:query:{uuid.uuid5(_NS, 'payments:1')}")
        self.assertNotEqual(first, g._stable_urn_for_query("payments", 0))
        self.assertEqual(first, g._stable_urn_for_query("payments", 1))


class EnforceStableUrnsTest(unittest.TestCase):
    def test_plural_list_gets_ordered_distinct_urns(self) -> None:
        plural = (
            "spec_version: 1\n"
            "golden_queries:\n"
            '  - stable_urn: "TBD"\n'
            "    name: Q1\n"
            "    sql: |\n"
            "      SELECT 1\n"
            '  - stable_urn: "TBD"\n'
            "    name: Q2\n"
            "    sql: |\n"
            "      SELECT 2\n"
        )
        out = g._enforce_stable_urns(plural, "demo")
        urns = [q["stable_urn"] for q in yaml.safe_load(out)["golden_queries"]]
        self.assertEqual(urns[0], g._stable_urn_for_query("demo", 0))
        self.assertEqual(urns[1], g._stable_urn_for_query("demo", 1))
        self.assertEqual(len(set(urns)), 2)

    def test_singular_legacy_form_gets_index_zero(self) -> None:
        singular = (
            "spec_version: 1\n"
            "golden_query:\n"
            '  stable_urn: "TBD"\n'
            "  name: Q1\n"
            "  sql: |\n"
            "    SELECT 1\n"
        )
        out = g._enforce_stable_urns(singular, "demo")
        urn = yaml.safe_load(out)["golden_query"]["stable_urn"]
        self.assertEqual(urn, g._stable_urn_for_query("demo", 0))


class InjectDescriptionTest(unittest.TestCase):
    _YAML = (
        "spec_version: 1\n"
        "kind: data_product_curated_entity\n"
        'product_display_name: "Widgets"\n'
        'product_description: "(placeholder)"\n'
        "data_product_id: widgets\n"
        "golden_query:\n"
        '  stable_urn: "TBD"\n'
        "  sql: |\n"
        "    SELECT a:b, x  -- colon and comment\n"
        "    FROM t WHERE y = 1\n"
    )

    def test_replaces_placeholder_and_preserves_sql_and_keys(self) -> None:
        out = g._inject_description(self._YAML, "Full body\n\nwith: colons and #hashes")
        parsed = yaml.safe_load(out)
        self.assertEqual(
            parsed["product_description"].strip(),
            "Full body\n\nwith: colons and #hashes",
        )
        self.assertTrue(parsed["golden_query"]["sql"].startswith("SELECT a:b, x"))
        self.assertEqual(parsed["data_product_id"], "widgets")

    def test_inserts_when_description_missing(self) -> None:
        without = self._YAML.replace('product_description: "(placeholder)"\n', "")
        out = g._inject_description(without, "Injected body")
        self.assertEqual(
            yaml.safe_load(out)["product_description"].strip(), "Injected body"
        )


if __name__ == "__main__":
    unittest.main()
