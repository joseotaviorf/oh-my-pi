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

## Ownership

**Data Owner:**
- widgets-owner@quintoandar.com.br

**Data Steward:**
- widgets-steward@quintoandar.com.br

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
            "## Ownership",
            "widgets-owner@quintoandar.com.br",
            "widgets-steward@quintoandar.com.br",
            "## Tables",
            "## Glossary and Synonyms",
            "## Golden Queries",
            "## DataHub catalog",
            "SELECT count(*)",
            "the thing.",
        ):
            self.assertNotIn(drop, self.desc)

    def test_excludes_where_to_query_and_synonyms_table(self) -> None:
        domain_md = """# Demo

## Overview

Core narrative.

## Where to query what

| You need… | Schema / table |
|---|---|
| counts | `dw_demo.fact_demo` |

## Synonyms

| Term | Meaning | Notes |
|---|---|---|
| **Demo** | demo entity | |

## Golden query: daily count

```sql
SELECT 1
```

## DataHub Catalog

- urn:li:dataProduct:demo
"""
        path = Path(self._tmp.name).with_name("domain_sample.md")
        path.write_text(domain_md, encoding="utf-8")
        desc = g._extract_description_from_md(path)
        self.assertIn("Core narrative", desc)
        for drop in (
            "## Where to query what",
            "## Synonyms",
            "## Golden query:",
            "## DataHub Catalog",
            "dw_demo.fact_demo",
        ):
            self.assertNotIn(drop, desc)
        path.unlink(missing_ok=True)

    def test_collapses_excess_blank_lines(self) -> None:
        self.assertNotIn("\n\n\n", self.desc)


class MetricDescriptionTest(unittest.TestCase):
    _METRIC_MD = """# NPS FR

## Ownership

**Data Owner:**
- nps-owner@quintoandar.com.br

**Data Steward:**
- nps-steward@quintoandar.com.br

## Overview

Official weighted NPS.

## Related Business Entities

- NPS

## MBR

- Support MBR
- Retention MBR

## Glossary and Synonyms

- **NPS True** → weighted average

## Scope

**Included**: all journeys

## Calculation

Formula here.

## Golden Queries

```sql
SELECT 1
```

## DataHub Catalog

- urn:li:dataProduct:nps-fr

## Superset Golden Assets

| You need… | Asset |
|-----------|-------|
| Official table | `sandbox.nps_fr` |
| Superset base | Chart — URN: `urn:li:dataset:(urn:li:dataPlatform:superset,16266,PROD)` |
"""

    def setUp(self) -> None:
        self._tmp = tempfile.NamedTemporaryFile(
            mode="w",
            suffix=".md",
            delete=False,
            encoding="utf-8",
            dir=tempfile.gettempdir(),
        )
        self._tmp.write(self._METRIC_MD)
        self._tmp.close()
        metric_dir = Path(tempfile.mkdtemp()) / "metric_entities"
        metric_dir.mkdir()
        self.md_path = metric_dir / "nps_fr.md"
        self.md_path.write_text(self._METRIC_MD, encoding="utf-8")
        self.desc = g._extract_description_from_md(self.md_path)

    def tearDown(self) -> None:
        self.md_path.unlink(missing_ok=True)
        self.md_path.parent.rmdir()

    def test_keeps_calculation_sections(self) -> None:
        for keep in ("## Overview", "## Scope", "## Calculation", "Formula here"):
            self.assertIn(keep, self.desc)

    def test_excludes_metric_routing_sections(self) -> None:
        for drop in (
            "## Ownership",
            "nps-owner@quintoandar.com.br",
            "nps-steward@quintoandar.com.br",
            "## Related Business Entities",
            "## MBR",
            "Support MBR",
            "Retention MBR",
            "## Glossary and Synonyms",
            "## Golden Queries",
            "## DataHub Catalog",
            "## Superset Golden Assets",
            "SELECT 1",
            "weighted average",
            "urn:li:dataset:(urn:li:dataPlatform:superset",
        ):
            self.assertNotIn(drop, self.desc)


class RelatedDataProductsTest(unittest.TestCase):
    def test_display_name_to_product_id(self) -> None:
        self.assertEqual(g._display_name_to_product_id("NPS"), "nps")
        self.assertEqual(
            g._display_name_to_product_id("House and Listing"),
            "house-and-listing",
        )

    def test_extract_from_section(self) -> None:
        metric_dir = Path(tempfile.mkdtemp()) / "metric_entities"
        metric_dir.mkdir()
        md_path = metric_dir / "demo_metric.md"
        md_path.write_text(
            "# Demo\n\n## Related Business Entities\n\n- NPS\n- Supply\n",
            encoding="utf-8",
        )
        self.assertEqual(g._extract_related_data_products(md_path), ["nps", "supply"])
        md_path.unlink()
        metric_dir.rmdir()


class MetricYamlPostProcessTest(unittest.TestCase):
    _YAML_WITH_MIXED_DATASETS = (
        "spec_version: 1\n"
        "data_product_type: metric\n"
        "datasets:\n"
        "  - schema: dw_nps\n"
        "    table: fact_nps\n"
        "golden_queries:\n"
        '  - stable_urn: "TBD"\n'
    )
    _SUPERSET_URN = "urn:li:dataset:(urn:li:dataPlatform:superset,16266,PROD)"

    def _metric_md(self, body: str) -> Path:
        metric_dir = Path(tempfile.mkdtemp()) / "metric_entities"
        metric_dir.mkdir()
        md_path = metric_dir / "demo.md"
        md_path.write_text(f"# Demo\n\n{body}\n", encoding="utf-8")
        return md_path

    def test_extract_metric_rows_trino_and_superset(self) -> None:
        md_path = self._metric_md(
            "## Superset Golden Assets\n\n"
            f"- **Chart** — `sandbox.nps_fr` — URN: `{self._SUPERSET_URN}`\n"
        )
        rows = g._extract_metric_dataset_rows(md_path)
        self.assertEqual(
            rows,
            [
                {"schema": "sandbox", "table": "nps_fr"},
                {"urn": self._SUPERSET_URN},
            ],
        )
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_metric_rows_legacy_superset_section(self) -> None:
        md_path = self._metric_md(
            "## Superset Golden Assets\n\n"
            f"- **Chart** — `sandbox.nps_ong_cohort` origin `{self._SUPERSET_URN}`\n"
        )
        rows = g._extract_metric_dataset_rows(md_path)
        self.assertEqual(
            rows,
            [
                {"schema": "sandbox", "table": "nps_ong_cohort"},
                {"urn": self._SUPERSET_URN},
            ],
        )
        md_path.unlink()
        md_path.parent.rmdir()

    def test_inject_metric_datasets_replaces_llm_block(self) -> None:
        md_path = self._metric_md(
            "## Superset Golden Assets\n\n"
            f"- **Chart** — `sandbox.nps_fr` — `{self._SUPERSET_URN}`\n"
        )
        out = g._inject_metric_datasets(self._YAML_WITH_MIXED_DATASETS, md_path)
        parsed = yaml.safe_load(out)
        self.assertEqual(len(parsed["datasets"]), 2)
        self.assertEqual(parsed["datasets"][0]["schema"], "sandbox")
        self.assertEqual(parsed["datasets"][1]["urn"], self._SUPERSET_URN)
        md_path.unlink()
        md_path.parent.rmdir()

    def test_inject_metric_datasets_empty_when_no_assets(self) -> None:
        md_path = self._metric_md("## Overview\n\nNo assets.\n")
        out = g._inject_metric_datasets(self._YAML_WITH_MIXED_DATASETS, md_path)
        parsed = yaml.safe_load(out)
        self.assertNotIn("datasets", parsed)
        md_path.unlink()
        md_path.parent.rmdir()

    def test_inject_related_data_products(self) -> None:
        out = g._inject_related_data_products(
            "data_product_type: metric\n", ["nps", "supply"]
        )
        parsed = yaml.safe_load(out)
        self.assertEqual(parsed["related_data_products"], ["nps", "supply"])

    def test_documentation_link_for_metric(self) -> None:
        metric_dir = Path(tempfile.mkdtemp()) / "metric_entities"
        metric_dir.mkdir()
        md_path = metric_dir / "nps_fr.md"
        md_path.write_text("# NPS FR\n", encoding="utf-8")
        link = g._documentation_link(md_path, "nps_fr")
        self.assertIn("Metric entity documentation", link["label"])
        self.assertIn("metric_entities/nps_fr.md", link["url"])
        md_path.unlink()
        metric_dir.rmdir()


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


class OwnersTest(unittest.TestCase):
    def _md(self, body: str) -> Path:
        tmp = Path(tempfile.mkdtemp()) / "entity.md"
        tmp.write_text(body, encoding="utf-8")
        return tmp

    def test_extract_owners_two_roles_multiple_emails_dedup(self) -> None:
        md_path = self._md(
            "# Demo\n\n## Ownership\n\n"
            "**Data Owner:**\n"
            "- felipe.abreu@quintoandar.com.br\n"
            "- carolina.espinoza@quintoandar.com.br\n"
            "- felipe.abreu@quintoandar.com.br\n\n"
            "**Data Steward:**\n"
            "- gustavo.silva@quintoandar.com.br\n\n"
            "## Overview\n\nBody.\n"
        )
        owners = g._extract_owners(md_path)
        self.assertEqual(
            owners["data_owner"],
            ["felipe.abreu@quintoandar.com.br", "carolina.espinoza@quintoandar.com.br"],
        )
        self.assertEqual(owners["data_steward"], ["gustavo.silva@quintoandar.com.br"])
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_owners_ignores_template_placeholders(self) -> None:
        md_path = self._md(
            "# Demo\n\n## Ownership\n\n"
            "**Data Owner:**\n"
            "- {data_owner_email@quintoandar.com.br}\n\n"
            "**Data Steward:**\n"
            "- {data_steward_email@quintoandar.com.br}\n"
        )
        owners = g._extract_owners(md_path)
        self.assertEqual(owners, {"data_owner": [], "data_steward": []})
        md_path.unlink()
        md_path.parent.rmdir()

    def test_inject_owners_emits_parseable_block(self) -> None:
        out = g._inject_owners(
            "data_product_type: domain\n",
            {
                "data_owner": ["a@quintoandar.com.br"],
                "data_steward": ["b@quintoandar.com.br"],
            },
        )
        parsed = yaml.safe_load(out)
        self.assertEqual(parsed["owners"]["data_owner"], ["a@quintoandar.com.br"])
        self.assertEqual(parsed["owners"]["data_steward"], ["b@quintoandar.com.br"])

    def test_inject_owners_empty_drops_block_and_strips_llm_authored(self) -> None:
        llm_yaml = (
            "data_product_type: domain\n"
            "owners:\n"
            "  data_owner:\n"
            "    - hallucinated@quintoandar.com.br\n"
        )
        out = g._inject_owners(llm_yaml, {"data_owner": [], "data_steward": []})
        parsed = yaml.safe_load(out)
        self.assertNotIn("owners", parsed)

    def test_inject_owners_omits_empty_role(self) -> None:
        out = g._inject_owners(
            "data_product_type: metric\n",
            {"data_owner": ["a@quintoandar.com.br"], "data_steward": []},
        )
        parsed = yaml.safe_load(out)
        self.assertEqual(parsed["owners"]["data_owner"], ["a@quintoandar.com.br"])
        self.assertNotIn("data_steward", parsed["owners"])


class MbrTest(unittest.TestCase):
    def _md(self, body: str) -> Path:
        tmp = Path(tempfile.mkdtemp()) / "entity.md"
        tmp.write_text(body, encoding="utf-8")
        return tmp

    def test_extract_mbrs_multiple_dedup_case_insensitive(self) -> None:
        md_path = self._md(
            "# Demo\n\n## MBR\n\n"
            "- Support MBR\n"
            "- Retention MBR\n"
            "- support mbr\n\n"
            "## Overview\n\nBody.\n"
        )
        self.assertEqual(g._extract_mbrs(md_path), ["Support MBR", "Retention MBR"])
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_mbrs_ignores_template_placeholder(self) -> None:
        md_path = self._md("# Demo\n\n## MBR\n\n- {MBR Name}\n")
        self.assertEqual(g._extract_mbrs(md_path), [])
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_mbrs_absent_section_returns_empty(self) -> None:
        md_path = self._md("# Demo\n\n## Overview\n\nNo MBR here.\n")
        self.assertEqual(g._extract_mbrs(md_path), [])
        md_path.unlink()
        md_path.parent.rmdir()

    def test_inject_mbr_emits_parseable_block(self) -> None:
        out = g._inject_mbr(
            "data_product_type: metric\n", ["Support MBR", "Retention MBR"]
        )
        parsed = yaml.safe_load(out)
        self.assertEqual(parsed["mbr"], ["Support MBR", "Retention MBR"])

    def test_inject_mbr_empty_drops_block_and_strips_llm_authored(self) -> None:
        llm_yaml = "data_product_type: metric\nmbr:\n  - Hallucinated MBR\n"
        out = g._inject_mbr(llm_yaml, [])
        parsed = yaml.safe_load(out)
        self.assertNotIn("mbr", parsed)

    def test_inject_mbr_anchors_after_data_product_type(self) -> None:
        out = g._inject_mbr("data_product_type: metric\n", ["Support MBR"])
        self.assertRegex(out, r"data_product_type: metric\nmbr:\n")


if __name__ == "__main__":
    unittest.main()
