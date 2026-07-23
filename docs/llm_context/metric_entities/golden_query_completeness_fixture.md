# Golden Query Completeness Fixture

<!--
TEST FIXTURE — not a production metric.

Purpose: manual and local-CI validation for PR #26537 (detect truncated/incomplete LLM
golden-query output when syncing entity Markdown to DataHub).

Incident this reproduces: Cases Perspective (`cases_perspective.md`) declared 9 golden
queries but a truncated LLM response published only 2 to DataHub while CI reported success.

This file mirrors that shape:
  • `## Golden Queries` plural section
  • 9 numbered `### Query N` sub-headings, each with a fenced ```sql block
  • `### Validation` prose after Query 9 — must NOT be counted as a 10th query

Do NOT register in docs/llm_context/intro.md. Do not merge to master without removing
or excluding from the DataHub push pipeline.

Quick checks (credential-free):

  uv run --directory packages/bietlejuice-compiler python -c "
  import sys; sys.path.insert(0, 'scripts/ci_cd')
  import generate_and_push_datahub_entities as g
  from pathlib import Path
  p = Path('../../docs/llm_context/metric_entities/golden_query_completeness_fixture.md')
  print('expected_golden_queries=', g._count_expected_golden_queries(p))
  "

Expected: expected_golden_queries= 9

Full pipeline (requires OPENAI_API_KEY, DATAHUB_* — local only):

  uv run --directory packages/bietlejuice-compiler python \\
    scripts/ci_cd/generate_and_push_datahub_entities.py \\
    docs/llm_context/metric_entities/golden_query_completeness_fixture.md
-->

## Ownership

**Data Owner:**
- data-platform@quintoandar.com.br

**Data Steward:**
- data-platform@quintoandar.com.br

## Overview

**Golden Query Completeness Fixture** is a synthetic metric entity used to exercise DataHub
golden-query completeness checks. It has no business meaning — only CI regression value.

## Related Business Entities

- Cases Perspective

## Glossary and Synonyms

- **truncation fixture**, **golden query completeness test** → this file

## Scope

**Included**: nothing — test fixture only.

**Excluded**: production use, TARS routing, dashboard consumption.

## Calculation

```
fixture_metric = COUNT(sql_blocks_in_golden_queries_section)
```

The correct count is **9**. A truncated LLM YAML with fewer `stable_urn:` entries must fail CI.

### Canonical Filter

Apply on the synthetic scope table:

```sql
fixture_scope.is_active = TRUE
AND fixture_scope.environment = 'test'
```

**Warning**: counting the `### Validation` subsection as a golden query produces a false
positive (10 instead of 9) and would let truncated output slip through.

## Dos and Don'ts

**Do:**

- Run `_count_expected_golden_queries()` before opening a PR that adds many golden queries.
- Treat `finish_reason == "length"` from LiteLLM as a hard failure.

**Don't:**

- Register this fixture in `intro.md`.
- Publish this fixture to production DataHub.

## Golden Queries

Nine component queries exercise the plural-heading counting zone. Each block is intentionally
multi-line so the Golden Queries section approaches token pressure without copying production SQL.

### Query 1 — Consolidated rate (fixture)

```sql
SELECT
    DATE_TRUNC('month', CAST(f.ref_date AS DATE)) AS ref_month,
    COUNT(DISTINCT CASE WHEN f.is_numerator THEN f.id_case END) AS numerator,
    COUNT(DISTINCT CASE WHEN f.is_denominator THEN f.id_case END) AS denominator,
    CAST(
        COUNT(DISTINCT CASE WHEN f.is_numerator THEN f.id_case END) AS DOUBLE
    ) / NULLIF(
        CAST(COUNT(DISTINCT CASE WHEN f.is_denominator THEN f.id_case END) AS DOUBLE),
        0
    ) AS rate_fixture
FROM sandbox.fixture_cases_perspective AS f
WHERE f.is_active = TRUE
    AND f.environment = 'test'
    AND f.ref_date >= DATE('<start_date>')
    AND f.ref_date < DATE('<end_date>') + INTERVAL '1' DAY
GROUP BY 1
ORDER BY 1
```

### Query 2 — Rate by operation with consolidated row (fixture)

```sql
WITH scoped AS (
    SELECT
        f.id_case,
        f.ref_date,
        f.is_numerator,
        f.is_denominator,
        f.operation_name
    FROM sandbox.fixture_cases_perspective AS f
    WHERE f.is_active = TRUE
        AND f.environment = 'test'
        AND f.ref_date >= DATE('<start_date>')
        AND f.ref_date < DATE('<end_date>') + INTERVAL '1' DAY
),
consolidated_month AS (
    SELECT
        DATE_TRUNC('month', CAST(ref_date AS DATE)) AS ref_month,
        CAST(
            COUNT(DISTINCT CASE WHEN is_numerator THEN id_case END) AS DOUBLE
        ) / NULLIF(
            CAST(COUNT(DISTINCT CASE WHEN is_denominator THEN id_case END) AS DOUBLE),
            0
        ) AS rate_fixture
    FROM scoped
    GROUP BY 1
),
operation_month AS (
    SELECT
        operation_name,
        DATE_TRUNC('month', CAST(ref_date AS DATE)) AS ref_month,
        CAST(
            COUNT(DISTINCT CASE WHEN is_numerator THEN id_case END) AS DOUBLE
        ) / NULLIF(
            CAST(COUNT(DISTINCT CASE WHEN is_denominator THEN id_case END) AS DOUBLE),
            0
        ) AS rate_fixture
    FROM scoped
    GROUP BY 1, 2
)
SELECT 0 AS sort_key, 'Post Contract' AS operation_name, ref_month, rate_fixture
FROM consolidated_month
UNION ALL
SELECT 1 AS sort_key, operation_name, ref_month, rate_fixture
FROM operation_month
ORDER BY sort_key, operation_name, ref_month
```

### Query 3 — Resolution rate consolidated (fixture)

```sql
SELECT
    DATE_TRUNC('month', CAST(f.ref_date AS DATE)) AS ref_month,
    COUNT(DISTINCT CASE WHEN f.is_resolved THEN f.id_case END) AS resolved_cases,
    COUNT(DISTINCT CASE WHEN f.has_resolution_survey THEN f.id_case END) AS surveyed_cases,
    CAST(COUNT(DISTINCT CASE WHEN f.is_resolved THEN f.id_case END) AS DOUBLE)
        / NULLIF(CAST(COUNT(DISTINCT CASE WHEN f.has_resolution_survey THEN f.id_case END) AS DOUBLE), 0)
        AS resolution_rate_fixture
FROM sandbox.fixture_cases_perspective AS f
WHERE f.is_active = TRUE
    AND f.environment = 'test'
    AND f.ref_date >= DATE('<start_date>')
    AND f.ref_date < DATE('<end_date>') + INTERVAL '1' DAY
GROUP BY 1
ORDER BY 1
```

### Query 4 — Resolution rate by operation (fixture)

```sql
WITH scoped AS (
    SELECT
        f.id_case,
        f.ref_date,
        f.is_resolved,
        f.has_resolution_survey,
        f.operation_name
    FROM sandbox.fixture_cases_perspective AS f
    WHERE f.is_active = TRUE
        AND f.environment = 'test'
        AND f.ref_date >= DATE('<start_date>')
        AND f.ref_date < DATE('<end_date>') + INTERVAL '1' DAY
)
SELECT
    operation_name,
    DATE_TRUNC('month', CAST(ref_date AS DATE)) AS ref_month,
    CAST(COUNT(DISTINCT CASE WHEN is_resolved THEN id_case END) AS DOUBLE)
        / NULLIF(CAST(COUNT(DISTINCT CASE WHEN has_resolution_survey THEN id_case END) AS DOUBLE), 0)
        AS resolution_rate_fixture
FROM scoped
GROUP BY 1, 2
ORDER BY 1, 2
```

### Query 5 — SLA consolidated (fixture)

```sql
SELECT
    DATE_TRUNC('month', CAST(f.solved_date AS DATE)) AS ref_month,
    COUNT(DISTINCT CASE WHEN f.is_solved_within_sla THEN f.id_case END) AS solved_within_sla,
    COUNT(DISTINCT CASE WHEN f.is_solved THEN f.id_case END) AS solved_cases,
    CAST(COUNT(DISTINCT CASE WHEN f.is_solved_within_sla THEN f.id_case END) AS DOUBLE)
        / NULLIF(CAST(COUNT(DISTINCT CASE WHEN f.is_solved THEN f.id_case END) AS DOUBLE), 0)
        AS sla_fixture
FROM sandbox.fixture_cases_perspective AS f
WHERE f.is_active = TRUE
    AND f.environment = 'test'
    AND f.solved_date >= DATE('<start_date>')
    AND f.solved_date < DATE('<end_date>') + INTERVAL '1' DAY
GROUP BY 1
ORDER BY 1
```

### Query 6 — SLA by operation (fixture)

```sql
WITH scoped AS (
    SELECT
        f.id_case,
        f.solved_date,
        f.is_solved_within_sla,
        f.is_solved,
        f.operation_name
    FROM sandbox.fixture_cases_perspective AS f
    WHERE f.is_active = TRUE
        AND f.environment = 'test'
        AND f.solved_date >= DATE('<start_date>')
        AND f.solved_date < DATE('<end_date>') + INTERVAL '1' DAY
)
SELECT
    operation_name,
    DATE_TRUNC('month', CAST(solved_date AS DATE)) AS ref_month,
    CAST(COUNT(DISTINCT CASE WHEN is_solved_within_sla THEN id_case END) AS DOUBLE)
        / NULLIF(CAST(COUNT(DISTINCT CASE WHEN is_solved THEN id_case END) AS DOUBLE), 0)
        AS sla_fixture
FROM scoped
GROUP BY 1, 2
ORDER BY 1, 2
```

### Query 7 — Inbound volume consolidated (fixture)

```sql
SELECT
    DATE_TRUNC('month', CAST(f.started_date AS DATE)) AS ref_month,
    COUNT(DISTINCT f.id_case) AS inbound_volume_fixture
FROM sandbox.fixture_cases_perspective AS f
WHERE f.is_active = TRUE
    AND f.environment = 'test'
    AND f.started_date >= DATE('<start_date>')
    AND f.started_date < DATE('<end_date>') + INTERVAL '1' DAY
GROUP BY 1
ORDER BY 1
```

### Query 8 — Outbound volume consolidated (fixture)

```sql
SELECT
    DATE_TRUNC('month', CAST(f.solved_date AS DATE)) AS ref_month,
    COUNT(DISTINCT f.id_case) AS outbound_volume_fixture
FROM sandbox.fixture_cases_perspective AS f
WHERE f.is_active = TRUE
    AND f.environment = 'test'
    AND f.solved_date >= DATE('<start_date>')
    AND f.solved_date < DATE('<end_date>') + INTERVAL '1' DAY
GROUP BY 1
ORDER BY 1
```

### Query 9 — Inbound volume by operation (fixture)

```sql
WITH scoped AS (
    SELECT
        f.id_case,
        f.started_date,
        f.operation_name
    FROM sandbox.fixture_cases_perspective AS f
    WHERE f.is_active = TRUE
        AND f.environment = 'test'
        AND f.started_date >= DATE('<start_date>')
        AND f.started_date < DATE('<end_date>') + INTERVAL '1' DAY
),
consolidated_month AS (
    SELECT
        DATE_TRUNC('month', CAST(started_date AS DATE)) AS ref_month,
        COUNT(DISTINCT id_case) AS inbound_volume_fixture
    FROM scoped
    GROUP BY 1
),
operation_month AS (
    SELECT
        operation_name,
        DATE_TRUNC('month', CAST(started_date AS DATE)) AS ref_month,
        COUNT(DISTINCT id_case) AS inbound_volume_fixture
    FROM scoped
    GROUP BY 1, 2
)
SELECT 0 AS sort_key, 'Post Contract' AS operation_name, ref_month, inbound_volume_fixture
FROM consolidated_month
UNION ALL
SELECT 1 AS sort_key, operation_name, ref_month, inbound_volume_fixture
FROM operation_month
ORDER BY sort_key, operation_name, ref_month
```

### Validation

This subsection is prose only — no fenced `sql` block. The counting logic must return **9**,
not **10**. A truncated LLM response that emits only Query 1 and Query 2 must be rejected:

```
expected = 9, actual = 2  →  ERROR (incomplete/truncated)
expected = 9, actual = 9  →  OK
```

## DataHub Catalog

- **This metric's data product**: `urn:li:dataProduct:golden-query-completeness-fixture`
