"""Unit tests for TARS entity YAML generator."""

from __future__ import annotations

import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[5]
_SYNC_DIR = _REPO_ROOT / "dags/governance/datahub_business_context"
if str(_SYNC_DIR) not in sys.path:
    sys.path.insert(0, str(_SYNC_DIR))

from sync.document_parser import parse_entity_markdown  # noqa: E402
from sync.yaml_generator import build_datahub_yaml, render_yaml  # noqa: E402

SAMPLE_MD = """\
# Payments

## Overview

Payments domain overview paragraph one.

## Tables

| You need… | Use this table |
|-----------|----------------|
| Fact | `dw_payments_platform.fact_payment` |

## Golden Queries

### Query 1 — Volume

Count payments.

```sql
SELECT COUNT(*) FROM dw_payments_platform.fact_payment;
```
"""


def test_build_datahub_yaml_structure():
    parsed = parse_entity_markdown(SAMPLE_MD)
    spec = build_datahub_yaml(
        parsed,
        data_product_id="payments",
        domain_urn="urn:li:domain:fintech",
        golden_query_stable_urn="urn:li:query:00000000-0000-0000-0000-000000000001",
    )
    assert spec["spec_version"] == 1
    assert spec["kind"] == "data_product_curated_entity"
    assert spec["data_product_id"] == "payments"
    assert spec["domain_urn"] == "urn:li:domain:fintech"
    assert spec["golden_query"]["stable_urn"].startswith("urn:li:query:")
    assert spec["datasets"][0]["schema"] == "dw_payments_platform"
    assert spec["datasets"][0]["table"] == "fact_payment"
    rendered = render_yaml(spec)
    assert "data_product_curated_entity" in rendered
    assert "schema: dw_payments_platform" in rendered
