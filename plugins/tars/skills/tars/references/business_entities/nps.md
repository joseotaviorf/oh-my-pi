# NPS

## Overview

NPS (Net Promoter Score) measures overall customer loyalty and brand perception at QuintoAndar. Unlike CSAT (which is per-ticket or per-interaction), NPS is collected through **structured campaigns** dispatched via the **Tracksale** platform.

NPS campaigns target specific customer segments at specific moments in the customer journey. Customers receive a survey asking "How likely are you to recommend QuintoAndar?" with a 0–10 scale:

| Score | Classification |
|-------|---------------|
| 0–6 | **detractor** |
| 7–8 | **passive** |
| 9–10 | **promoter** |

**NPS = % promoters − % petractors**

Each NPS answer may include a **justification** — free-text feedback explaining the score.

## Synonyms

- **NPS**, **Net Promoter Score**, **nota NPS** → `nps`
- **Pesquisa NPS**, **campanha NPS** → NPS campaign/dispatch
- **Promotor** → promoter (9–10)
- **Detrator** → detractor (0–6)
- **Justificativa** → justification (free-text feedback)

## Tables

| You need... | Use this table |
|-------------|----------------|
| NPS campaign dispatches (who was surveyed and when) | `dw_customer_satisfaction.fact_nps_dispatches` |
| Customer-level NPS aggregations | `dw_customer_satisfaction.fact_nps_customer_metrics` |
| Justification text per NPS answer | `dw_customer_satisfaction.fact_nps_answer_justifications` |
| NPS campaign definitions | `dw_customer_satisfaction.dim_nps_campaign` |
| NPS answer dimension | `dw_customer_satisfaction.dim_nps_answer` |
| Raw NPS answers from Tracksale (raw) | `tracksale_clean.answer` |
| NPS campaign definitions (raw) | `tracksale_clean.campaign` |
| NPS dispatches (raw) | `tracksale_clean.dispatch` |
| NPS target share per segment (from GSheets) | `gsheets_clean.nps_target_share` |

### Key columns in `fact_nps_dispatches`

| Column | Description |
|--------|-------------|
| `sk_nps_dispatch` | Primary surrogate key |
| `sk_dispatch` | Dispatch identifier |
| `sk_nps_campaign` | Campaign the dispatch belongs to |
| `sk_nps_customer`, `sk_user` | Customer and user identifiers |
| `sk_nps_answer` | Link to the answer dimension |
| `sk_contract`, `sk_offer`, `sk_booking` | Linked business entities |
| `sk_created_date`, `sk_sent_date`, `sk_answered_date` | Date surrogate keys |
| `score` | 0–10 score given by the customer |
| `dispatch_status` | Status of the dispatch |
| `is_answered` | Whether the customer responded |
| `has_comment` | Whether the answer includes a comment |
| `minutes_response_time` | Time to respond in minutes |

### Key columns in `fact_nps_customer_metrics`

| Column | Description |
|--------|-------------|
| `sk_nps_customer`, `sk_user` | Customer identifiers |
| `total_dispatches`, `total_answers` | Volume metrics |
| `answers_as_promoter`, `answers_as_detractor` | Classification counts |
| `avg_score`, `last_score` | Score metrics |
| `overall_nps` | Overall NPS for this customer |
| `answer_rate`, `comment_rate` | Engagement rates |

### Key columns in `fact_nps_answer_justifications`

| Column | Description |
|--------|-------------|
| `sk_nps_answer` | Link to the answer |
| `level` | Justification level |
| `justification` | Free-text justification |

### Key columns in `dim_nps_campaign`

| Column | Description |
|--------|-------------|
| `sk_nps_campaign` | Surrogate key |
| `name` | Campaign name |
| `main_channel` | Primary channel |
| `business_context` | Business context |
| `customer_journey` | Journey stage |
| `purpose` | Campaign purpose |
| `customer_type` | Target customer type |
| `metric_group` | Metric grouping |

### Key columns in `dim_nps_answer`

| Column | Description |
|--------|-------------|
| `sk_nps_answer` | Surrogate key |
| `campaign_step` | Step within the campaign |
| `score_category` | Score classification (Promoter, Passive, Detractor) |
| `comment` | Answer comment text |
| `is_customer_identified` | Whether customer is identified |
| `ts_answered` | When the answer was submitted |

### Grain and joins

- **`fact_nps_dispatches`**: 1 row per dispatch (one survey sent to one customer)
- **`fact_nps_customer_metrics`**: 1 row per customer (aggregated NPS metrics)
- **`fact_nps_answer_justifications`**: 1 row per justification text, joined via `sk_nps_answer`
- **Campaign join**: `fact_nps_dispatches.sk_nps_campaign = dim_nps_campaign.sk_nps_campaign`
- **Answer join**: `fact_nps_dispatches.sk_nps_answer = dim_nps_answer.sk_nps_answer`

## Key Metrics

- **NPS score** — % Promoters − % Detractors (use `dim_nps_answer.score_category` for classification)
- **Response rate** — dispatches answered / total dispatches
- **NPS by campaign** — NPS segmented by campaign type (journey moment)
- **NPS trend** — NPS evolution per period
- **Detractor volume** — count of detractors per period
- **Justification analysis** — free-text analysis from `fact_nps_answer_justifications`

## Relationships with Other Entities

### Customer (N:1 — many dispatches to one customer)

JOIN via `sk_nps_customer` or `sk_user` for customer context. `fact_nps_customer_metrics` provides customer-level aggregated NPS.

### Campaign (N:1 — many dispatches to one campaign)

JOIN via `sk_nps_campaign` to `dim_nps_campaign` for campaign metadata (name, channel, journey).

### Contract (N:1 — dispatch may be linked to a contract)

JOIN via `sk_contract` in `fact_nps_dispatches` for contract context.

### Offboarding NPS

NPS collected during offboarding is already filtered in `datalake_offboarding.nps` and `datalake_offboarding.nps_agg`. These feed into the offboarding context (see Termination entity) but also comes from the Tracksale-based NPS that is in `dw_customer_satisfaction`.

## Dos and Don'ts

**Do:**
- Use `dw_customer_satisfaction` tables for Tracksale-based NPS analysis
- Use `fact_nps_dispatches` as the primary fact table for NPS analysis
- Join with `dim_nps_campaign` on `sk_nps_campaign` for campaign segmentation
- Use `dim_nps_answer.score_category` for promoter/passive/detractor classification, always using low case
- Use `fact_nps_answer_justifications` for qualitative analysis — join on `sk_nps_answer`
- Compute NPS as `% Promoters − % Detractors` (not as an average score)

**Don't:**
- Don't confuse NPS (brand loyalty, Tracksale) with CSAT (per-ticket satisfaction, multiple sources) — they are separate entities in separate DW schemas
- Don't use average NPS score as the metric — NPS is defined as `% Promoters − % Detractors`
- Don't ignore the response rate — low response rates make NPS unreliable
- Don't use `sk_campaign` or `sk_answer` — the correct key names include the `nps_` prefix: `sk_nps_campaign`, `sk_nps_answer`

## Golden Queries

### Query 1 — Monthly NPS trend

NPS score trend by month using `dim_nps_answer.score_category` for classification.

```sql
SELECT
    date_trunc('month', CAST(dna.ts_answered AS TIMESTAMP)) AS month_answered,
    COUNT(*) AS total_responses,
    SUM(CASE WHEN dna.score_category = 'promoter' THEN 1 ELSE 0 END) AS promoters,
    SUM(CASE WHEN dna.score_category = 'detractor' THEN 1 ELSE 0 END) AS detractors,
    (CAST(SUM(CASE WHEN dna.score_category = 'promoter' THEN 1 ELSE 0 END) AS DOUBLE)
     - CAST(SUM(CASE WHEN dna.score_category = 'detractor' THEN 1 ELSE 0 END) AS DOUBLE))
     / COUNT(*) * 100 AS nps_score
FROM dw_customer_satisfaction.fact_nps_dispatches AS fnd
INNER JOIN dw_customer_satisfaction.dim_nps_answer AS dna
    ON fnd.sk_nps_answer = dna.sk_nps_answer
WHERE fnd.is_answered = true
    AND dna.ts_answered >= DATE '2025-01-01'
GROUP BY 1
```

### Query 2 — NPS by campaign

NPS segmented by campaign for understanding journey-specific satisfaction.

```sql
SELECT
    dnc.name AS campaign_name,
    dnc.customer_journey,
    dnc.business_context,
    COUNT(*) AS total_responses,
    SUM(CASE WHEN dna.score_category = 'promoter' THEN 1 ELSE 0 END) AS promoters,
    SUM(CASE WHEN dna.score_category = 'passive' THEN 1 ELSE 0 END) AS passives,
    SUM(CASE WHEN dna.score_category = 'detractor' THEN 1 ELSE 0 END) AS detractors,
    (CAST(SUM(CASE WHEN dna.score_category = 'promoter' THEN 1 ELSE 0 END) AS DOUBLE)
     - CAST(SUM(CASE WHEN dna.score_category = 'detractor' THEN 1 ELSE 0 END) AS DOUBLE))
     / COUNT(*) * 100 AS nps_score
FROM dw_customer_satisfaction.fact_nps_dispatches AS fnd
INNER JOIN dw_customer_satisfaction.dim_nps_answer AS dna
    ON fnd.sk_nps_answer = dna.sk_nps_answer
LEFT JOIN dw_customer_satisfaction.dim_nps_campaign AS dnc
    ON fnd.sk_nps_campaign = dnc.sk_nps_campaign
WHERE fnd.is_answered = true
    AND dna.ts_answered >= DATE '2025-01-01'
GROUP BY 1, 2, 3
```

### Query 3 — Detractor justifications

Justification texts from detractors for root cause analysis.

```sql
SELECT
    dnc.name AS campaign_name,
    fnd.score,
    fnj.justification,
    dna.ts_answered
FROM dw_customer_satisfaction.fact_nps_answer_justifications AS fnj
INNER JOIN dw_customer_satisfaction.fact_nps_dispatches AS fnd
    ON fnj.sk_nps_answer = fnd.sk_nps_answer
INNER JOIN dw_customer_satisfaction.dim_nps_answer AS dna
    ON fnd.sk_nps_answer = dna.sk_nps_answer
LEFT JOIN dw_customer_satisfaction.dim_nps_campaign AS dnc
    ON fnd.sk_nps_campaign = dnc.sk_nps_campaign
WHERE dna.score_category = 'detractor'
    AND dna.ts_answered >= DATE '2025-01-01'
```
