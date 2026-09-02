# Sale Type Offer/Event Propagation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Propagate offer-level `sale_type` from `core_sale_offer` through `sale_offer` and `dw_sale.fact_offers`, then expose it on both visit-derived and offer-derived rows in `dw_sale.fact_sale_demand_event`.

**Architecture:** Preserve each source grain. Visit event arms read `sale_type` from `dw_sale.fact_visits`; offer event arms read it from `dw_sale.fact_offers`. Do not join the visit and offer paths or derive offer classification from the listing-level market table.

**Tech Stack:** Spark SQL on Databricks DBR 16.4 and EMR Spark 3.5, DAG Builder query-delta workflows, YAML governance metadata, sqlglot lineage validation, Woodpecker CI.

## Global Constraints

- Use nullable `sale_type` with `PRIMARY` and `SECONDARY` values.
- Preserve NULL for Firestore-only, historical, or otherwise unclassified source rows.
- Keep existing offer and event grains unchanged.
- Do not add `is_primary_market` in this slice.
- Do not join `listing_sale_type`.
- Do not modify `dim_offer`, `dim_sale_agreement`, buyer-prospect, listing, closing, or NPS tables.
- Do not modify DAG declarations or generated dependencies unless validation proves an existing dependency is missing.
- Run the Databricks/EMR SQL lint immediately after every edited `.sql` file.
- Use `uv run`; never use bare `python3`, `pip`, or a hand-created virtual environment.

---

### Task 1: Propagate `sale_type` through the enrich offer table

**Files:**
- Modify: `dags/for_sale/enrich_sale_offer/queries/enrich/sale_offer.sql` top-level projection
- Modify: `dags/for_sale/enrich_sale_offer/metadata/enrich/sale_offer.yml`

**Interfaces:**
- Consumes: `datalake_sale_offer.core_sale_offer.sale_type`
- Produces: `datalake_sale_offer.sale_offer.sale_type`

- [ ] **Step 1: Add the direct projection**

Add `o.sale_type` to the top-level `sale_offer` projection after the offer identity columns and before the existing 3P boolean fields. Do not transform the value:

```sql
  o.id_house,
  o.id_owner,
  o.id_region,
  o.sale_type,
  r.city_group,
```

- [ ] **Step 2: Document the enrich column**

Add `sale_type` to `metadata/enrich/sale_offer.yml` with:

```yaml
  sale_type:
    lineage:
    - datalake_sale_offer.core_sale_offer.sale_type
    description: Market type of the offer persisted by Sales Flow. PRIMARY identifies a new-build unit offer and SECONDARY identifies a resale offer. NULL is preserved when the upstream offer has no classification.
    categories:
      PRIMARY: Offer for a Primary Market (new-build) unit.
      SECONDARY: Offer for a Secondary Market (resale) listing.
```

- [ ] **Step 3: Run SQL lint immediately**

Run:

```bash
uv run --project packages/bietlejuice-compiler python packages/bietlejuice-compiler/scripts/ci_cd/validate_join_shapes.py \
  --paths dags/for_sale/enrich_sale_offer/queries/enrich/sale_offer.sql --json
```

Expected: `violations` is empty. Run the textual Databricks/EMR construct scan required by `databricks-emr-sql-lint`; report findings if any.

- [ ] **Step 4: Validate this pair**

Run:

```bash
PYTHONPATH=.:packages/bietlejuice-compiler uv run --project packages/bietlejuice-compiler \
  python packages/bietlejuice-compiler/scripts/governance_metadata_validation/validate_lineage_consistency.py \
  -f dags/for_sale/enrich_sale_offer/metadata/enrich/sale_offer.yml
```

Expected: one file passes lineage consistency.

- [ ] **Step 5: Commit the pair**

```bash
rtk git add dags/for_sale/enrich_sale_offer/queries/enrich/sale_offer.sql \
  dags/for_sale/enrich_sale_offer/metadata/enrich/sale_offer.yml
rtk git commit -m "feat(enrich_sale_offer): propagate sale_type"
```

### Task 2: Propagate `sale_type` into `dw_sale.fact_offers`

**Files:**
- Modify: `dags/for_sale/dw_sale_offers/queries/dw/fact_offers.sql`
- Modify: `dags/for_sale/dw_sale_offers/metadata/dw/fact_offers.yml`

**Interfaces:**
- Consumes: `datalake_sale_offer.sale_offer.sale_type`
- Produces: `dw_sale.fact_offers.sale_type`

- [ ] **Step 1: Add the direct projection**

Add `eso.sale_type` to the fact projection before the existing 3P booleans:

```sql
    eso.sale_price_agreed,
    eso.sale_type,
    eso.has_used_fgts_in_payment,
    eso.is_buyer_first_offer,
```

- [ ] **Step 2: Document the DW column**

Add `sale_type` to `metadata/dw/fact_offers.yml` with:

```yaml
  sale_type:
    lineage:
    - datalake_sale_offer.sale_offer.sale_type
    description: Market type of each offer. Propagated from the Sales Flow offer classification through the enriched sale-offer table; PRIMARY identifies a new-build unit and SECONDARY identifies a resale offer. NULL is preserved when the source is unclassified.
    categories:
      PRIMARY: Offer for a Primary Market (new-build) unit.
      SECONDARY: Offer for a Secondary Market (resale) listing.
```

- [ ] **Step 3: Run SQL lint immediately**

Run join-shape validation and the textual Databricks/EMR construct scan on:

```bash
uv run --project packages/bietlejuice-compiler python packages/bietlejuice-compiler/scripts/ci_cd/validate_join_shapes.py \
  --paths dags/for_sale/dw_sale_offers/queries/dw/fact_offers.sql --json
```

Expected: `violations` is empty and the EMR construct scan reports no findings.

- [ ] **Step 4: Validate this pair**

Run the file-scoped lineage validator for:

```text
dags/for_sale/dw_sale_offers/metadata/dw/fact_offers.yml
```

Expected: one file passes lineage consistency.

- [ ] **Step 5: Commit the pair**

```bash
rtk git add dags/for_sale/dw_sale_offers/queries/dw/fact_offers.sql \
  dags/for_sale/dw_sale_offers/metadata/dw/fact_offers.yml
rtk git commit -m "feat(dw_sale_offers): propagate sale_type"
```

### Task 3: Propagate both paths into `fact_sale_demand_event`

**Files:**
- Modify: `dags/for_sale/dw_sale_events/queries/dw/fact_sale_demand_event.sql`
- Modify: `dags/for_sale/dw_sale_events/metadata/dw/fact_sale_demand_event.yml`

**Interfaces:**
- Consumes: `dw_sale.fact_visits.sale_type` and `dw_sale.fact_offers.sale_type`
- Produces: nullable `dw_sale.fact_sale_demand_event.sale_type`

- [ ] **Step 1: Add source columns to the two input CTEs**

Add `fv.sale_type` to `bookings` and `fo.sale_type` to `offers`, before the existing 3P booleans:

```sql
        fv.sk_listing_price_segment,
        fv.sale_type,
        fv.is_3p_supply,
```

```sql
        fo.sk_listing_price_segment,
        fo.sale_type,
        fo.is_3p_supply,
```

- [ ] **Step 2: Thread the column through every event arm**

In every `UNION ALL` arm, project `sale_type` in the same position:

- Booking-derived arms (`VISIT_BOOKED`, `VISIT_COMPLETED`, `VISIT_CANCELED`) use `sale_type` from `bookings`.
- Offer-derived arms (`OFFER_SUBMITTED`, `OFFER_ACCEPTED`, `SALE_AGREEMENT_CREATED`, `SALE_AGREEMENT_SIGNED`, `OFFER_DISMISSED`) use `sale_type` from `offers`.

Because `offers.sale_type` is sourced from `fact_offers`, unclassified offer rows remain NULL without a join or fallback.

- [ ] **Step 3: Add the final projection and grouping**

Add `e.sale_type` to `final_results`, add `sale_type` to the outer SELECT, and add it to the final `GROUP BY`:

```sql
    COALESCE(e.sk_listing_price_segment, -1) AS sk_listing_price_segment,
    e.sale_type,
    COALESCE(e.is_3p_supply, FALSE) AS is_3p_supply,
```

- [ ] **Step 4: Document dual lineage**

Add `sale_type` to `metadata/dw/fact_sale_demand_event.yml` with lineage to both source facts:

```yaml
  sale_type:
    lineage:
    - dw_sale.fact_visits.sale_type
    - dw_sale.fact_offers.sale_type
    description: Market type associated with the demand-funnel event. Visit-derived events use the visit classification and offer-derived events use the offer classification. PRIMARY identifies a new-build unit and SECONDARY identifies a resale offer; NULL is preserved for unclassified source rows.
    categories:
      PRIMARY: Event associated with a Primary Market offer or visit.
      SECONDARY: Event associated with a Secondary Market offer or visit.
```

- [ ] **Step 5: Run SQL lint immediately**

Run:

```bash
uv run --project packages/bietlejuice-compiler python packages/bietlejuice-compiler/scripts/ci_cd/validate_join_shapes.py \
  --paths dags/for_sale/dw_sale_events/queries/dw/fact_sale_demand_event.sql --json
```

Expected: `violations` is empty and the EMR construct scan reports no findings.

- [ ] **Step 6: Validate this pair**

Run the file-scoped lineage validator for:

```text
dags/for_sale/dw_sale_events/metadata/dw/fact_sale_demand_event.yml
```

Expected: one file passes lineage consistency.

- [ ] **Step 7: Commit the pair**

```bash
rtk git add dags/for_sale/dw_sale_events/queries/dw/fact_sale_demand_event.sql \
  dags/for_sale/dw_sale_events/metadata/dw/fact_sale_demand_event.yml
rtk git commit -m "feat(dw_sale_events): propagate sale_type from visits and offers"
```

### Task 4: Integrated verification and branch handoff

**Files:**
- Verify: `dags/dependencies.yaml`
- Verify: all six SQL/metadata files changed by Tasks 1–3

- [ ] **Step 1: Run static propagation assertions**

Use this repository-root command:

```bash
uv run --no-project python - <<'PY'
from pathlib import Path

checks = {
    "dags/for_sale/enrich_sale_offer/queries/enrich/sale_offer.sql": [
        "o.sale_type",
    ],
    "dags/for_sale/dw_sale_offers/queries/dw/fact_offers.sql": [
        "eso.sale_type",
    ],
    "dags/for_sale/dw_sale_events/queries/dw/fact_sale_demand_event.sql": [
        "fv.sale_type",
        "fo.sale_type",
        "e.sale_type",
    ],
}

for filename, snippets in checks.items():
    text = Path(filename).read_text()
    for snippet in snippets:
        assert snippet in text, f"{snippet!r} missing from {filename}"

event_sql = Path(
    "dags/for_sale/dw_sale_events/queries/dw/fact_sale_demand_event.sql"
).read_text()
assert event_sql.count("sale_type") >= 12
assert "CAST(NULL AS STRING) AS sale_type" not in event_sql

metadata = Path(
    "dags/for_sale/dw_sale_events/metadata/dw/fact_sale_demand_event.yml"
).read_text()
for snippet in ("dw_sale.fact_visits.sale_type", "dw_sale.fact_offers.sale_type"):
    assert snippet in metadata, f"{snippet!r} missing from event metadata"
PY
```

Expected: no assertion output and exit code 0. The typed NULL is not needed in the event query because `fact_offers.sale_type` is the propagated nullable source; Firestore NULL handling belongs to `core_sale_offer`.

- [ ] **Step 2: Validate metadata and lineage**

Run:

```bash
make validate-metadata-files-content
make validate-lineage-consistency
CI_COMMIT_BRANCH=$(rtk git branch --show-current) make validate-fair-metadata
```

Expected: all changed metadata passes schema, lineage, and FAIR checks.

- [ ] **Step 3: Validate SQL runtime shape and style**

Run:

```bash
make check-style-dags
make validate-join-shapes paths=dags/for_sale/enrich_sale_offer
make validate-join-shapes paths=dags/for_sale/dw_sale_offers
make validate-join-shapes paths=dags/for_sale/dw_sale_events
```

Expected: style passes and all join-shape reports contain no violations.

- [ ] **Step 4: Confirm generated dependencies are unchanged**

Run:

```bash
rtk git diff -- dags/dependencies.yaml
```

Expected: no diff, because the implementation only projects columns from existing upstream tables and introduces no new table reference.

- [ ] **Step 5: Inspect final diff**

Run:

```bash
rtk git diff origin/master...HEAD --stat
rtk git diff origin/master...HEAD --check
rtk git status -sb
```

Expected: only the approved design/plan documents and six SQL/metadata files are changed; whitespace check passes; no secrets or unrelated files are present.

- [ ] **Step 6: Push the separate branch and open the PR**

Push `feat/sale-type-offer-event` and create a draft PR from `origin/master` after all checks pass. Do not alter the already merged core-offer PR.
