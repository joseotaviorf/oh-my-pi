"""Unit tests for the DataHub entity generate script's pure helpers.

Covers the behaviors that protect the manual audit from CI regressions:
  * description extraction (full MD body minus assets/glossary/golden-query sections)
  * deterministic per-query stable URNs (index 0 == legacy value)
  * multi-golden-query stable-URN enforcement over both YAML forms
  * description injection that survives a YAML round-trip without mangling SQL blocks
  * golden-query completeness validation (regression: Cases Perspective incident,
    9 golden queries in the Markdown but only 2 reached DataHub because the LLM
    response was truncated and nothing detected the mismatch)
"""

import tempfile
import unittest
import uuid
from pathlib import Path
from unittest import mock

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

## Related Domain Entities

- NPS

## Catalog

| Metric | Type |
| :---- | :---- |
| NPS True | OKR |
| NPS Onboarding | Health Metric |

## MBR

**Name** Support MBR
**Category** Experience

**Name** Retention MBR
**Category** Retention

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
            "## Related Domain Entities",
            "## MBR",
            "Support MBR",
            "Retention MBR",
            "## Catalog",
            "NPS Onboarding",
            "## Glossary and Synonyms",
            "## Golden Queries",
            "## DataHub Catalog",
            "## Superset Golden Assets",
            "SELECT 1",
            "weighted average",
            "urn:li:dataset:(urn:li:dataPlatform:superset",
        ):
            self.assertNotIn(drop, self.desc)

    def test_keeps_targets_and_okrs_section(self) -> None:
        md_with_targets = self._METRIC_MD.replace(
            "## Golden Queries",
            "## Targets and OKRs\n\n"
            "**OKR** — period goal.\n\n"
            "- **Source table:** `datalake_gsheets_clean.target_service_kpis`\n"
            "- **Filter key / metric name:** `SLA VT Onb + Off s/ Despejo`\n\n"
            "## Golden Queries",
        )
        self.md_path.write_text(md_with_targets, encoding="utf-8")
        desc = g._extract_description_from_md(self.md_path)
        self.assertIn("## Targets and OKRs", desc)
        self.assertIn("datalake_gsheets_clean.target_service_kpis", desc)
        self.assertIn("SLA VT Onb + Off s/ Despejo", desc)


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
            "# Demo\n\n## Related Domain Entities\n\n- NPS\n- Supply\n",
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

    def test_extract_metric_rows_chart_and_dashboard_urns(self) -> None:
        chart_urn = "urn:li:chart:(superset,chart.56400)"
        dashboard_urn = "urn:li:dashboard:(superset,dashboard.123)"
        md_path = self._metric_md(
            "## Superset Golden Assets\n\n"
            f"- **Dataset** — `sandbox.nps_fr` — URN: `{self._SUPERSET_URN}`\n"
            f"- **Chart** — URN: `{chart_urn}`\n"
            f"- **Dashboard** — URN: `{dashboard_urn}`\n"
        )
        rows = g._extract_metric_dataset_rows(md_path)
        self.assertEqual(
            rows,
            [
                {"schema": "sandbox", "table": "nps_fr"},
                {"urn": self._SUPERSET_URN},
                {"urn": chart_urn},
                {"urn": dashboard_urn},
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


class DomainYamlPostProcessTest(unittest.TestCase):
    """Domain entity ``datasets:`` come from ``## Tables``, not the LLM block."""

    _YAML_WITH_LLM_DATASETS = (
        "spec_version: 1\n"
        "data_product_type: domain\n"
        "datasets:\n"
        "  - schema: dw_llm\n"
        "    table: hallucinated\n"
        "golden_queries:\n"
        '  - stable_urn: "TBD"\n'
    )

    def _domain_md(self, body: str) -> Path:
        domain_dir = Path(tempfile.mkdtemp()) / "domain_entities"
        domain_dir.mkdir()
        md_path = domain_dir / "demo.md"
        md_path.write_text(f"# Demo\n\n{body}\n", encoding="utf-8")
        return md_path

    def test_extract_domain_rows_from_tables_section(self) -> None:
        md_path = self._domain_md(
            "## Tables\n\n"
            "| You need | Use |\n"
            "|---|---|\n"
            "| Canonical classification | `datalake_sale_primary_market.listing_sale_type` |\n"
            "| Visit facts (owned elsewhere) | `dw_visit.fact_visits` |\n"
            "\n"
            "## Golden Queries\n\n"
            "```sql\nSELECT 1 FROM dw_sale.dim_listing\n```\n"
        )
        rows = g._extract_domain_dataset_rows(md_path)
        self.assertEqual(
            rows,
            [
                {
                    "schema": "datalake_sale_primary_market",
                    "table": "listing_sale_type",
                },
                {"schema": "dw_visit", "table": "fact_visits"},
            ],
        )
        md_path.unlink()
        md_path.parent.rmdir()

    def test_inject_domain_datasets_replaces_llm_block(self) -> None:
        md_path = self._domain_md(
            "## Tables\n\n- `datalake_sale_primary_market.house_development`\n"
        )
        out = g._inject_domain_datasets(self._YAML_WITH_LLM_DATASETS, md_path)
        parsed = yaml.safe_load(out)
        self.assertEqual(
            parsed["datasets"],
            [
                {
                    "schema": "datalake_sale_primary_market",
                    "table": "house_development",
                }
            ],
        )
        md_path.unlink()
        md_path.parent.rmdir()

    def test_inject_domain_datasets_empty_when_no_tables(self) -> None:
        md_path = self._domain_md("## Overview\n\nNo table refs.\n")
        out = g._inject_domain_datasets(self._YAML_WITH_LLM_DATASETS, md_path)
        parsed = yaml.safe_load(out)
        self.assertNotIn("datasets", parsed)
        md_path.unlink()
        md_path.parent.rmdir()


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


class ExtractGoldenQuerySqlsTest(unittest.TestCase):
    """``_extract_golden_query_sqls`` is the read-side of the SQL-injection fix: it
    must return the exact same count, in the exact same order, as
    ``_count_expected_golden_queries`` — that invariant is what lets
    ``_inject_golden_query_sqls`` do positional injection safely."""

    def test_plural_section_returns_sqls_in_order(self) -> None:
        tmp_dir = Path(tempfile.mkdtemp())
        md_path = tmp_dir / "demo.md"
        md_path.write_text(
            "# Demo\n\n## Golden Queries\n\n"
            "### Query 1 — demo\n\n```sql\nSELECT 1\n```\n\n"
            "### Query 2 — demo\n\n```sql\nSELECT 2\nFROM t\n```\n",
            encoding="utf-8",
        )
        self.assertEqual(
            g._extract_golden_query_sqls(md_path), ["SELECT 1", "SELECT 2\nFROM t"]
        )
        md_path.unlink()
        tmp_dir.rmdir()

    def test_singular_heading_with_h3_subqueries_returns_all_three(self) -> None:
        """Same shape as agents.md (Bugbot regression): one singular heading with
        two extra H3 sub-queries must yield 3 SQL texts, not 1."""
        tmp_dir = Path(tempfile.mkdtemp())
        md_path = tmp_dir / "demo.md"
        md_path.write_text(
            "# Demo\n\n"
            "## Golden query: Active agents per hub (latest day)\n\n"
            "```sql\nSELECT 1\n```\n\n"
            "### Reconciliation: BigAgent vs Nazaré revenue share\n\n"
            "```sql\nSELECT 2\n```\n\n"
            "### CIQ portfolio loss (Compra de Carteira)\n\n"
            "```sql\nSELECT 3\n```\n\n"
            "## DataHub Catalog\n\n- urn:li:dataProduct:demo\n",
            encoding="utf-8",
        )
        self.assertEqual(
            g._extract_golden_query_sqls(md_path), ["SELECT 1", "SELECT 2", "SELECT 3"]
        )
        self.assertEqual(len(g._extract_golden_query_sqls(md_path)), 3)
        md_path.unlink()
        tmp_dir.rmdir()

    def test_absent_returns_empty_list(self) -> None:
        tmp_dir = Path(tempfile.mkdtemp())
        md_path = tmp_dir / "demo.md"
        md_path.write_text(
            "# Demo\n\n## Overview\n\nNo queries yet.\n", encoding="utf-8"
        )
        self.assertEqual(g._extract_golden_query_sqls(md_path), [])
        md_path.unlink()
        tmp_dir.rmdir()

    def test_count_matches_count_expected_golden_queries(self) -> None:
        """Invariant relied on by _inject_golden_query_sqls's positional injection."""
        tmp_dir = Path(tempfile.mkdtemp())
        md_path = tmp_dir / "demo.md"
        queries = "\n\n".join(
            f"### Query {i} — demo\n\n```sql\nSELECT {i}\n```" for i in range(1, 6)
        )
        md_path.write_text(
            f"# Demo\n\n## Golden Queries\n\n{queries}\n", encoding="utf-8"
        )
        self.assertEqual(
            len(g._extract_golden_query_sqls(md_path)),
            g._count_expected_golden_queries(md_path),
        )
        md_path.unlink()
        tmp_dir.rmdir()


class InjectGoldenQuerySqlsTest(unittest.TestCase):
    """``_inject_golden_query_sqls`` overwrites the LLM's placeholder ``sql:`` with
    the real Markdown text — this is the fix that makes query-text truncation
    structurally impossible (the SQL never round-trips through the LLM)."""

    def test_plural_list_placeholder_replaced_by_position(self) -> None:
        yaml_content = (
            "spec_version: 1\n"
            "golden_queries:\n"
            '  - stable_urn: "TBD"\n'
            "    name: Q1\n"
            '    sql: "(injected by CI from Markdown)"\n'
            '  - stable_urn: "TBD"\n'
            "    name: Q2\n"
            '    sql: "(injected by CI from Markdown)"\n'
        )
        out = g._inject_golden_query_sqls(
            yaml_content, ["SELECT 1", "SELECT 2\nFROM t"]
        )
        parsed = yaml.safe_load(out)
        self.assertEqual(parsed["golden_queries"][0]["sql"].strip(), "SELECT 1")
        self.assertEqual(parsed["golden_queries"][1]["sql"].strip(), "SELECT 2\nFROM t")
        # Names/other keys must survive untouched.
        self.assertEqual(parsed["golden_queries"][0]["name"], "Q1")
        self.assertEqual(parsed["golden_queries"][1]["name"], "Q2")

    def test_singular_form_placeholder_replaced(self) -> None:
        yaml_content = (
            "spec_version: 1\n"
            "golden_query:\n"
            '  stable_urn: "TBD"\n'
            "  name: Q1\n"
            '  sql: "(injected by CI from Markdown)"\n'
        )
        out = g._inject_golden_query_sqls(yaml_content, ["SELECT 1"])
        parsed = yaml.safe_load(out)
        self.assertEqual(parsed["golden_query"]["sql"].strip(), "SELECT 1")

    def test_replaces_llm_authored_block_scalar_too(self) -> None:
        """The LLM might ignore the placeholder instruction and emit a real (but
        wrong/incomplete) ``sql: |`` block anyway — injection must still overwrite
        it, not just the single-line placeholder form."""
        yaml_content = (
            "spec_version: 1\n"
            "golden_query:\n"
            '  stable_urn: "TBD"\n'
            "  sql: |\n"
            "    SELECT this_is_wrong_or_truncat\n"
        )
        out = g._inject_golden_query_sqls(
            yaml_content, ["SELECT the_real_full_query\nFROM t"]
        )
        parsed = yaml.safe_load(out)
        self.assertEqual(
            parsed["golden_query"]["sql"].strip(), "SELECT the_real_full_query\nFROM t"
        )

    def test_preserves_special_characters_and_multiline_sql(self) -> None:
        """Literal block scalars need no escaping — colons, quotes, and comments in
        real SQL must round-trip exactly."""
        real_sql = (
            "SELECT a:b, 'quoted', x -- a comment\nFROM t\nWHERE y = 1 AND z <> 2"
        )
        yaml_content = (
            "spec_version: 1\n"
            "golden_queries:\n"
            '  - stable_urn: "TBD"\n'
            '    sql: "(injected by CI from Markdown)"\n'
        )
        out = g._inject_golden_query_sqls(yaml_content, [real_sql])
        parsed = yaml.safe_load(out)
        self.assertEqual(parsed["golden_queries"][0]["sql"].strip(), real_sql)

    def test_count_mismatch_falls_back_to_llm_authored_content(self) -> None:
        """If the LLM dropped an entire golden-query entry, the count of 'sql:' keys
        in the YAML won't match len(sqls) — injection must be a no-op (the existing
        completeness check catches the drop instead of this function silently
        mis-attaching SQL to the wrong query)."""
        yaml_content = (
            "spec_version: 1\n"
            "golden_queries:\n"
            '  - stable_urn: "TBD"\n'
            '    sql: "(injected by CI from Markdown)"\n'
        )
        out = g._inject_golden_query_sqls(yaml_content, ["SELECT 1", "SELECT 2"])
        self.assertEqual(out, yaml_content)

    def test_no_expected_sqls_is_a_noop(self) -> None:
        yaml_content = "spec_version: 1\nproduct_display_name: Demo\n"
        out = g._inject_golden_query_sqls(yaml_content, [])
        self.assertEqual(out, yaml_content)

    def test_end_to_end_matches_markdown_source_for_many_queries(self) -> None:
        """Regression: even with 9 golden queries (Cases Perspective shape) and only
        placeholders from the LLM, every published SQL text must exactly match the
        Markdown source after injection — the fix that makes the original incident
        (9 declared, 2 delivered) structurally impossible for the SQL text itself."""
        tmp_dir = Path(tempfile.mkdtemp())
        md_path = tmp_dir / "demo.md"
        queries_md = "\n\n".join(
            f"### Query {i} — demo\n\n```sql\nSELECT {i} FROM table_{i}\n```"
            for i in range(1, 10)
        )
        md_path.write_text(
            f"# Demo\n\n## Golden Queries\n\n{queries_md}\n", encoding="utf-8"
        )

        llm_output = "spec_version: 1\ngolden_queries:\n" + "".join(
            f'  - stable_urn: "TBD"\n    name: Query {i}\n'
            '    sql: "(injected by CI from Markdown)"\n'
            for i in range(1, 10)
        )
        sqls = g._extract_golden_query_sqls(md_path)
        self.assertEqual(len(sqls), 9)
        out = g._inject_golden_query_sqls(llm_output, sqls)
        parsed = yaml.safe_load(out)
        self.assertEqual(len(parsed["golden_queries"]), 9)
        for i, query in enumerate(parsed["golden_queries"], start=1):
            self.assertEqual(query["sql"].strip(), f"SELECT {i} FROM table_{i}")

        md_path.unlink()
        tmp_dir.rmdir()


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

    def test_extract_owners_unwraps_mailto_links(self) -> None:
        md_path = self._md(
            "# Demo\n\n## Ownership\n\n"
            "**Data Owner:**\n"
            "- [owner@quintoandar.com.br](mailto:owner@quintoandar.com.br)\n\n"
            "**Data Steward:**\n"
            "- [steward@quintoandar.com.br](mailto:steward@quintoandar.com.br)\n"
        )
        owners = g._extract_owners(md_path)
        self.assertEqual(owners["data_owner"], ["owner@quintoandar.com.br"])
        self.assertEqual(owners["data_steward"], ["steward@quintoandar.com.br"])
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_owners_accepts_quintoandar_com_and_com_br(self) -> None:
        md_path = self._md(
            "# Demo\n\n## Ownership\n\n"
            "**Data Owner:**\n"
            "- owner@quintoandar.com\n\n"
            "**Data Steward:**\n"
            "- steward@quintoandar.com.br\n"
        )
        owners = g._extract_owners(md_path)
        self.assertEqual(owners["data_owner"], ["owner@quintoandar.com"])
        self.assertEqual(owners["data_steward"], ["steward@quintoandar.com.br"])
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_owners_ignores_pre_ownership_heading(self) -> None:
        md_path = self._md(
            "# Demo\n\n## Pre-ownership\n\n"
            "**Data Owner:**\n"
            "- decoy@quintoandar.com.br\n\n"
            "## **Ownership**\n\n"
            "**Data Owner:**\n"
            "- owner@quintoandar.com.br\n\n"
            "**Data Steward:**\n"
            "- steward@quintoandar.com.br\n"
        )
        owners = g._extract_owners(md_path)
        self.assertEqual(owners["data_owner"], ["owner@quintoandar.com.br"])
        self.assertEqual(owners["data_steward"], ["steward@quintoandar.com.br"])
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

    def test_extract_mbrs_name_and_category_pair(self) -> None:
        md_path = self._md(
            "# Demo\n\n## MBR\n\n"
            "**Name** Post Contract\n"
            "**Category** Quality\n\n"
            "## Overview\n\nBody.\n"
        )
        self.assertEqual(
            g._extract_mbrs(md_path),
            [{"name": "Post Contract", "category": "Quality"}],
        )
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_mbrs_multiple_pairs_dedup_case_insensitive(self) -> None:
        md_path = self._md(
            "# Demo\n\n## MBR\n\n"
            "**Name** Support MBR\n"
            "**Category** Experience\n\n"
            "**Name** Retention MBR\n"
            "**Category** Retention\n\n"
            "**Name** support mbr\n"
            "**Category** Experience\n"
        )
        self.assertEqual(
            g._extract_mbrs(md_path),
            [
                {"name": "Support MBR", "category": "Experience"},
                {"name": "Retention MBR", "category": "Retention"},
            ],
        )
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_mbrs_accepts_colon_inside_bold(self) -> None:
        md_path = self._md(
            "# Demo\n\n## MBR\n\n**Name:** Post Contract\n**Category:** Quality\n"
        )
        self.assertEqual(
            g._extract_mbrs(md_path),
            [{"name": "Post Contract", "category": "Quality"}],
        )
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_mbrs_unfilled_category_placeholder_yields_name_only(self) -> None:
        md_path = self._md(
            "# Demo\n\n## MBR\n\n**Name** Post Contract\n**Category** {category}\n"
        )
        self.assertEqual(g._extract_mbrs(md_path), [{"name": "Post Contract"}])
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_mbrs_ignores_template_placeholder(self) -> None:
        md_path = self._md(
            "# Demo\n\n## MBR\n\n**Name** {MBR Name}\n**Category** {category}\n"
        )
        self.assertEqual(g._extract_mbrs(md_path), [])
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_mbrs_absent_section_returns_empty(self) -> None:
        md_path = self._md("# Demo\n\n## Overview\n\nNo MBR here.\n")
        self.assertEqual(g._extract_mbrs(md_path), [])
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_mbrs_still_reads_legacy_bullet_form(self) -> None:
        """A doc not yet migrated to Name/Category must keep publishing membership."""
        md_path = self._md("# Demo\n\n## **MBR**\n\n- Post Contract\n")
        self.assertEqual(g._extract_mbrs(md_path), [{"name": "Post Contract"}])
        md_path.unlink()
        md_path.parent.rmdir()

    def test_inject_mbr_emits_parseable_block(self) -> None:
        out = g._inject_mbr(
            "data_product_type: metric\n",
            [
                {"name": "Support MBR", "category": "Experience"},
                {"name": "Retention MBR"},
            ],
        )
        parsed = yaml.safe_load(out)
        self.assertEqual(
            parsed["mbr"],
            [
                {"name": "Support MBR", "category": "Experience"},
                {"name": "Retention MBR"},
            ],
        )

    def test_inject_mbr_empty_drops_block_and_strips_llm_authored(self) -> None:
        llm_yaml = "data_product_type: metric\nmbr:\n  - name: Hallucinated MBR\n"
        out = g._inject_mbr(llm_yaml, [])
        parsed = yaml.safe_load(out)
        self.assertNotIn("mbr", parsed)

    def test_inject_mbr_anchors_after_data_product_type(self) -> None:
        out = g._inject_mbr("data_product_type: metric\n", [{"name": "Support MBR"}])
        self.assertRegex(out, r"data_product_type: metric\nmbr:\n")


class CatalogTest(unittest.TestCase):
    def _md(self, body: str) -> Path:
        tmp = Path(tempfile.mkdtemp()) / "entity.md"
        tmp.write_text(body, encoding="utf-8")
        return tmp

    def test_extract_catalog_reads_metric_and_type_rows(self) -> None:
        md_path = self._md(
            "# Demo\n\n## Catalog\n\n"
            "| Metric | Type |\n"
            "| :---- | :---- |\n"
            "| NPS True | OKR |\n"
            "| NPS Onboarding | Health Metric |\n\n"
            "## Overview\n\nBody.\n"
        )
        self.assertEqual(
            g._extract_catalog(md_path),
            [
                {"name": "NPS True", "type": "OKR"},
                {"name": "NPS Onboarding", "type": "Health Metric"},
            ],
        )
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_catalog_normalizes_type_casing(self) -> None:
        md_path = self._md(
            "# Demo\n\n## Catalog\n\n"
            "| Metric | Type |\n| :---- | :---- |\n"
            "| A | okr |\n| B | health metric |\n"
        )
        self.assertEqual(
            [row["type"] for row in g._extract_catalog(md_path)],
            ["OKR", "Health Metric"],
        )
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_catalog_dedups_case_insensitively(self) -> None:
        md_path = self._md(
            "# Demo\n\n## Catalog\n\n"
            "| Metric | Type |\n| :---- | :---- |\n"
            "| NPS True | OKR |\n| nps true | Health Metric |\n"
        )
        self.assertEqual(
            g._extract_catalog(md_path), [{"name": "NPS True", "type": "OKR"}]
        )
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_catalog_keeps_escaped_pipe_in_metric_name(self) -> None:
        """``EC|ES2CS`` is a real metric name; Markdown escapes its pipe as ``\\|``."""
        md_path = self._md(
            "# Demo\n\n## Catalog\n\n"
            "| Metric | Type |\n| :---- | :---- |\n"
            "| EC\\|ES2CS | OKR |\n"
        )
        self.assertEqual(
            g._extract_catalog(md_path), [{"name": "EC|ES2CS", "type": "OKR"}]
        )
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_catalog_ignores_template_placeholders(self) -> None:
        md_path = self._md(
            "# Demo\n\n## Catalog\n\n"
            "| Metric | Type |\n| :---- | :---- |\n"
            "| {Official Metric Name} | {OKR \\| Health Metric} |\n"
        )
        self.assertEqual(g._extract_catalog(md_path), [])
        md_path.unlink()
        md_path.parent.rmdir()

    def test_extract_catalog_ignores_datahub_catalog_section(self) -> None:
        """``## DataHub Catalog`` is a tooling pointer, not the metric catalog."""
        md_path = self._md(
            "# Demo\n\n## DataHub Catalog\n\n"
            "| Metric | Type |\n| :---- | :---- |\n| Stray | OKR |\n"
        )
        self.assertEqual(g._extract_catalog(md_path), [])
        md_path.unlink()
        md_path.parent.rmdir()

    def test_inject_catalog_emits_parseable_block(self) -> None:
        out = g._inject_catalog(
            "data_product_type: metric\n",
            [{"name": "NPS True", "type": "OKR"}, {"name": "NPS Onboarding"}],
        )
        parsed = yaml.safe_load(out)
        self.assertEqual(
            parsed["catalog"],
            [{"name": "NPS True", "type": "OKR"}, {"name": "NPS Onboarding"}],
        )

    def test_inject_catalog_empty_drops_block_and_strips_llm_authored(self) -> None:
        llm_yaml = "data_product_type: metric\ncatalog:\n  - name: Hallucinated\n"
        out = g._inject_catalog(llm_yaml, [])
        self.assertNotIn("catalog", yaml.safe_load(out))

    def test_inject_catalog_anchors_after_data_product_type(self) -> None:
        out = g._inject_catalog(
            "data_product_type: metric\n", [{"name": "NPS True", "type": "OKR"}]
        )
        self.assertRegex(out, r"data_product_type: metric\ncatalog:\n")


class CatalogTypeRequiredTest(unittest.TestCase):
    """A metric published to DataHub must always carry a recognized Type.

    ``curated_push_catalog`` embeds the type directly into each
    ``data_product.metrics`` value (e.g. ``"NPS True (OKR)"``), so an unclassified
    metric can no longer be silently published — ``_validate_catalog_types`` is the
    single gate that turns a missing/invalid Type into a hard error in ``main()``.
    """

    def test_all_rows_classified_returns_no_errors(self) -> None:
        catalog = [
            {"name": "NPS True", "type": "OKR"},
            {"name": "NPS Onboarding", "type": "Health Metric"},
        ]
        self.assertEqual(g._validate_catalog_types(catalog), [])

    def test_empty_catalog_returns_no_errors(self) -> None:
        self.assertEqual(g._validate_catalog_types([]), [])

    def test_row_missing_type_key_is_reported(self) -> None:
        catalog = [{"name": "NPS True", "type": "OKR"}, {"name": "Untyped Metric"}]
        self.assertEqual(g._validate_catalog_types(catalog), ["Untyped Metric"])

    def test_row_with_unrecognized_type_is_reported(self) -> None:
        """A typo'd/unknown Type cell (e.g. "KPI") must fail, not pass through verbatim."""
        catalog = [{"name": "Weird Metric", "type": "KPI"}]
        self.assertEqual(g._validate_catalog_types(catalog), ["Weird Metric"])

    def test_extract_catalog_with_blank_type_cell_fails_validation(self) -> None:
        """End-to-end: a Markdown row with an empty Type cell must be rejected."""
        md_path = self._md(
            "# Demo\n\n## Catalog\n\n"
            "| Metric | Type |\n| :---- | :---- |\n"
            "| NPS True | OKR |\n| Untyped Metric |  |\n"
        )
        catalog = g._extract_catalog(md_path)
        self.assertEqual(g._validate_catalog_types(catalog), ["Untyped Metric"])
        md_path.unlink()
        md_path.parent.rmdir()

    def _md(self, body: str) -> Path:
        tmp = Path(tempfile.mkdtemp()) / "entity.md"
        tmp.write_text(body, encoding="utf-8")
        return tmp


class GoldenQueryCompletenessTest(unittest.TestCase):
    """Regression coverage for the Cases Perspective incident.

    PR #26285 added a metric entity Markdown with 9 golden queries; the LLM
    response was silently truncated and only 2 reached the generated YAML
    (and therefore DataHub). ``main()`` had no check comparing the Markdown's
    declared query count against the YAML's, so the partial publish was
    reported as a success. These tests pin the counting helpers that now
    detect that mismatch.
    """

    def _metric_md_with_queries(self, n: int) -> Path:
        queries = "\n\n".join(
            f"### Query {i} — demo\n\n```sql\nSELECT {i}\n```" for i in range(1, n + 1)
        )
        body = (
            f"# Demo\n\n## Golden Queries\n\n{queries}\n\n"
            "## DataHub Catalog\n\n- urn:li:dataProduct:demo\n"
        )
        metric_dir = Path(tempfile.mkdtemp()) / "metric_entities"
        metric_dir.mkdir()
        md_path = metric_dir / "demo.md"
        md_path.write_text(body, encoding="utf-8")
        return md_path

    def test_count_expected_golden_queries_plural_subheadings(self) -> None:
        md_path = self._metric_md_with_queries(9)
        self.assertEqual(g._count_expected_golden_queries(md_path), 9)
        md_path.unlink()
        md_path.parent.rmdir()

    def test_count_expected_golden_queries_singular_domain_headings(self) -> None:
        tmp_dir = Path(tempfile.mkdtemp())
        md_path = tmp_dir / "demo.md"
        md_path.write_text(
            "# Demo\n\n"
            "## Golden query: Query A\n\n```sql\nSELECT 1\n```\n\n"
            "## Golden query: Query B\n\n```sql\nSELECT 2\n```\n\n"
            "## DataHub Catalog\n\n- urn:li:dataProduct:demo\n",
            encoding="utf-8",
        )
        self.assertEqual(g._count_expected_golden_queries(md_path), 2)
        md_path.unlink()
        tmp_dir.rmdir()

    def test_count_expected_golden_queries_singular_heading_with_h3_subqueries(
        self,
    ) -> None:
        """Regression (Bugbot, PR #26537): agents.md has one
        '## Golden query: {Name}' H2 that itself contains two extra queries as H3
        sub-sections ("### Reconciliation ..." / "### CIQ portfolio loss ...").
        Counting the singular heading as a hard '1' undercounts real queries and
        would let a truncated LLM response (only the first query emitted) pass the
        completeness check."""
        tmp_dir = Path(tempfile.mkdtemp())
        md_path = tmp_dir / "demo.md"
        md_path.write_text(
            "# Demo\n\n"
            "## Golden query: Active agents per hub (latest day)\n\n"
            "```sql\nSELECT 1\n```\n\n"
            "### Reconciliation: BigAgent vs Nazaré revenue share\n\n"
            "```sql\nSELECT 2\n```\n\n"
            "### CIQ portfolio loss (Compra de Carteira)\n\n"
            "```sql\nSELECT 3\n```\n\n"
            "## DataHub Catalog\n\n- urn:li:dataProduct:demo\n",
            encoding="utf-8",
        )
        self.assertEqual(g._count_expected_golden_queries(md_path), 3)
        md_path.unlink()
        tmp_dir.rmdir()

    def test_count_expected_golden_queries_ignores_non_query_subheadings(self) -> None:
        """Regression: Cases Perspective's Golden Queries section ends with a
        '### Validation' sub-heading after Query 9 — that must not be counted
        as a 10th query."""
        tmp_dir = Path(tempfile.mkdtemp())
        md_path = tmp_dir / "demo.md"
        md_path.write_text(
            "# Demo\n\n## Golden Queries\n\n"
            "### Query 1 — demo\n\n```sql\nSELECT 1\n```\n\n"
            "### Query 2 — demo\n\n```sql\nSELECT 2\n```\n\n"
            "### Validation\n\nRun both queries and compare totals.\n\n"
            "## Superset Golden Assets\n\n- n/a\n",
            encoding="utf-8",
        )
        self.assertEqual(g._count_expected_golden_queries(md_path), 2)
        md_path.unlink()
        tmp_dir.rmdir()

    def test_count_expected_golden_queries_handles_non_numbered_headings(self) -> None:
        """Real docs (e.g. visits.md, losses.md) use ### headings with no 'Query'
        word at all — numbered ('### 1. ...') or a bare descriptive title. Counting
        must work regardless of heading text, by counting ```sql fences instead."""
        tmp_dir = Path(tempfile.mkdtemp())
        md_path = tmp_dir / "demo.md"
        md_path.write_text(
            "# Demo\n\n## Golden queries\n\n"
            "### 1. Some descriptive title\n\n```sql\nSELECT 1\n```\n\n"
            "### Another title with no numbering\n\n```sql\nSELECT 2\n```\n",
            encoding="utf-8",
        )
        self.assertEqual(g._count_expected_golden_queries(md_path), 2)
        md_path.unlink()
        tmp_dir.rmdir()

    def test_count_expected_golden_queries_absent_returns_zero(self) -> None:
        tmp_dir = Path(tempfile.mkdtemp())
        md_path = tmp_dir / "demo.md"
        md_path.write_text(
            "# Demo\n\n## Overview\n\nNo queries yet.\n", encoding="utf-8"
        )
        self.assertEqual(g._count_expected_golden_queries(md_path), 0)
        md_path.unlink()
        tmp_dir.rmdir()

    def test_count_golden_queries_in_yaml_plural(self) -> None:
        yaml_content = (
            "spec_version: 1\n"
            "golden_queries:\n"
            '  - stable_urn: "TBD"\n'
            "    name: Q1\n"
            '  - stable_urn: "TBD"\n'
            "    name: Q2\n"
        )
        self.assertEqual(g._count_golden_queries_in_yaml(yaml_content), 2)

    def test_count_golden_queries_in_yaml_singular(self) -> None:
        yaml_content = 'spec_version: 1\ngolden_query:\n  stable_urn: "TBD"\n'
        self.assertEqual(g._count_golden_queries_in_yaml(yaml_content), 1)

    def test_count_golden_queries_in_yaml_none(self) -> None:
        self.assertEqual(g._count_golden_queries_in_yaml("spec_version: 1\n"), 0)

    def test_regression_truncated_llm_output_detected_as_incomplete(self) -> None:
        """Pins the exact Cases Perspective shape: 9 declared, 2 delivered."""
        md_path = self._metric_md_with_queries(9)
        truncated_yaml = (
            "spec_version: 1\n"
            "golden_queries:\n"
            '  - stable_urn: "TBD"\n'
            "    name: Query 1\n"
            '  - stable_urn: "TBD"\n'
            "    name: Query 2\n"
        )
        expected = g._count_expected_golden_queries(md_path)
        actual = g._count_golden_queries_in_yaml(truncated_yaml)
        self.assertEqual(expected, 9)
        self.assertEqual(actual, 2)
        self.assertLess(actual, expected)
        md_path.unlink()
        md_path.parent.rmdir()

    def test_complete_output_is_not_flagged(self) -> None:
        md_path = self._metric_md_with_queries(2)
        complete_yaml = (
            "spec_version: 1\n"
            "golden_queries:\n"
            '  - stable_urn: "TBD"\n'
            '  - stable_urn: "TBD"\n'
        )
        expected = g._count_expected_golden_queries(md_path)
        actual = g._count_golden_queries_in_yaml(complete_yaml)
        self.assertEqual(expected, actual)
        md_path.unlink()
        md_path.parent.rmdir()


class CallLlmTruncationTest(unittest.TestCase):
    """Regression: a LiteLLM response with ``finish_reason: length`` means the

    model ran out of output tokens mid-YAML (exactly what happened for Cases
    Perspective's 9 large SQL golden queries). ``_call_llm`` must raise instead
    of returning the truncated content as if it were a complete response.
    """

    def _mock_response(self, finish_reason: str, content: str = "spec_version: 1\n"):
        response = mock.MagicMock()
        response.raise_for_status.return_value = None
        response.json.return_value = {
            "choices": [
                {"finish_reason": finish_reason, "message": {"content": content}}
            ]
        }
        return response

    @mock.patch("scripts.ci_cd.generate_and_push_datahub_entities.requests.post")
    def test_raises_when_finish_reason_is_length(self, mock_post) -> None:
        mock_post.return_value = self._mock_response("length")
        with self.assertRaises(ValueError):
            g._call_llm([], "model", "http://litellm", "key", max_tokens=16000)

    @mock.patch("scripts.ci_cd.generate_and_push_datahub_entities.requests.post")
    def test_passes_through_on_normal_completion(self, mock_post) -> None:
        mock_post.return_value = self._mock_response(
            "stop", "spec_version: 1\nkind: x\n"
        )
        result = g._call_llm([], "model", "http://litellm", "key", max_tokens=16000)
        self.assertEqual(result, "spec_version: 1\nkind: x\n")

    @mock.patch("scripts.ci_cd.generate_and_push_datahub_entities.requests.post")
    def test_max_tokens_forwarded_in_payload(self, mock_post) -> None:
        mock_post.return_value = self._mock_response("stop")
        g._call_llm([], "model", "http://litellm", "key", max_tokens=16000)
        _, kwargs = mock_post.call_args
        self.assertEqual(kwargs["json"]["max_tokens"], 16000)


class ChangedMdsSkipsDeletedFilesTest(unittest.TestCase):
    """Regression: pipeline 85577 (push-datahub-business-context on the PR that
    removed the golden-query-completeness-fixture entity) crashed with a bare
    ``FileNotFoundError`` mislabeled as "LLM call failed". ``git diff --name-only``
    lists deleted paths too, and DataHub publish has no delete/archive path — a
    deleted MD must be skipped, not passed to ``_build_messages`` where it 404s.
    """

    def test_deleted_md_is_skipped_kept_md_is_returned(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            md_dir = repo_root / "docs" / "llm_context" / "metric_entities"
            md_dir.mkdir(parents=True)
            kept = md_dir / "kept.md"
            kept.write_text("# Kept\n")
            # deleted.md is intentionally never created on disk — it only exists in
            # the git-diff output, mirroring a file removed by the triggering push.
            changed_files = [
                "docs/llm_context/metric_entities/deleted.md",
                "docs/llm_context/metric_entities/kept.md",
            ]

            with (
                mock.patch.object(g, "_REPO_ROOT", repo_root),
                mock.patch.object(
                    g, "_MD_PREFIXES", ("docs/llm_context/metric_entities/",)
                ),
                mock.patch.object(g, "_git_changed_files", return_value=changed_files),
            ):
                result = g._changed_mds()

        self.assertEqual(result, [kept])

    def test_all_deleted_returns_empty_list_not_a_crash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            (repo_root / "docs" / "llm_context" / "metric_entities").mkdir(parents=True)
            changed_files = ["docs/llm_context/metric_entities/deleted_only.md"]

            with (
                mock.patch.object(g, "_REPO_ROOT", repo_root),
                mock.patch.object(
                    g, "_MD_PREFIXES", ("docs/llm_context/metric_entities/",)
                ),
                mock.patch.object(g, "_git_changed_files", return_value=changed_files),
            ):
                result = g._changed_mds()

        self.assertEqual(result, [])


if __name__ == "__main__":
    unittest.main()
