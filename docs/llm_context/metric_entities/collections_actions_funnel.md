# Collections Actions Funnel

## Ownership

**Data Owner:**
- maxsuel.alves@quintoandar.com.br

**Data Steward:**
- maxsuel.alves@quintoandar.com.br

## Overview

**Collections Actions Funnel** measures how effectively the T2 directly-collectable delinquent portfolio is worked through the collection-activation process, from first contact attempt to a paid negotiation. This entity covers five official Health Metrics, all measured at contract grain: **Spin** (contact intensity — average contact attempts per contract per elapsed business day), **% Alô** (share of contracts with a successfully answered call), **% CPC** (share of contracts with a confirmed contact with the right person), **% Promessa** (share of contracts with a negotiation promise recorded), and **% Acordo** (share of contracts with a paid negotiation) — each expressed as a share of the total contract population in scope, per business day.

This entity backs the **Ações de Cobrança** `[Fintech][P&P]` Superset dashboard (57 charts), including a parallel breakdown of every metric by `advisory` for collection-agency performance monitoring.

## Related Domain Entities

- **T2 Overdue Portfolio** (`t2_overdue_portfolio_context.md`) — source table (`sandbox.t2_fact_overdue_portfolio_timeline`), full field glossary, and the contract-level dedup pattern this entity depends on. URN: `urn:li:dataset:(urn:li:dataPlatform:trino,hive.sandbox.t2_fact_overdue_portfolio_timeline,PROD)`

## Catalog

| Metric | Type |
| :---- | :---- |
| Spin | Health Metric |
| % Alô (Successful Contacted Contracts) | Health Metric |
| % CPC (Successful CPC Contracts) | Health Metric |
| % Promessa (Successful Promises Generated) | Health Metric |
| % Acordo (Successful Payment Negotiation) | Health Metric |

## Glossary and Synonyms

- **Funil**, **Funil de Acionamentos**, **Funil de Cobrança**, **Collection Funnel**, **Activation Funnel**, **Contact Funnel**, **Collections Contracts Actions Funnel** → this entity.
- **Spin** → contact-intensity member metric; `SUM(esforço) / COUNT(DISTINCT contract) / MAX(business_day elapsed)`.
- **Alô** / **Alo** / **Contacted** → the % Alô member (call answered, `alo > 0`).
- **CPC** → the % CPC member (confirmed contact with the right person, `cpc > 0`).
- **Promessa** / **Promise** → the % Promessa member (a negotiation promise recorded).
- **Acordo** / **Acordo Pago** / **Payment Negotiation** (as a funnel stage) → the % Acordo member (a paid negotiation, `dt_down_payment IS NOT NULL`). **Not the same metric as the separate "Colchão Effectiveness" / "Acordos" entity** (see near-miss below) — this member is a contract-level conversion share within the activation funnel, not a currency recovery amount.
- **Near-miss — "Acordos", "Colchão de Acordos", "Efetividade de Acordo", "Agreement Recovery"** → a different, separate metric entity measuring recovered *amount* on the negotiated/regularized portfolio segment. Do not resolve those terms against this entity.
- **`GRB`** → appeared as an `advisory`-like label in audit-only chart titles on the same dashboard ("Audit GRB Logs Vol..."); **unconfirmed whether it is a real collection agency** or a vendor/integration name — do not add to the confirmed advisory list without validation.

## Scope

**Included**: contracts in the T2 directly-collectable delinquent population (`collectable_delinquent_portfolio = TRUE`), deduplicated to one row per contract per reference date (prioritizing a still-open invoice, else the most recently paid one) — the same population and dedup pattern used by the production Superset queries behind this dashboard.

**Excluded**: invoices under an active negotiation (the regularized/"colchão" portfolio) — that population belongs to the separate Colchão Effectiveness / Agreement Recovery entity, not this one.

## Calculation

```
Spin      = SUM(esforco) / COUNT(DISTINCT sk_contract) / MAX(business_day)
% Alô     = COUNT(DISTINCT contracts where alo > 0)      / COUNT(DISTINCT all contracts in scope)
% CPC     = COUNT(DISTINCT contracts where cpc > 0)      / COUNT(DISTINCT all contracts in scope)
% Promessa= COUNT(DISTINCT contracts with a promise)     / COUNT(DISTINCT all contracts in scope)
% Acordo  = COUNT(DISTINCT contracts with a paid deal)   / COUNT(DISTINCT all contracts in scope)
```

Each rate is a **share of the total contract population in scope on that business day** — not a step-to-step conversion. A related but distinct family of production charts ("Actioned to Contacted Conversion Rate", "Contacted to CPC Conversion Rate", "CPC to Promisse Conversion Rate", "Promisse to Negotiation Conversion Rate") computes **step-over-step conversion** instead (e.g. contracts reaching CPC ÷ contracts that were already contacted) — both formulas are real production patterns; see Nuances before assuming which one a chart uses.

### Canonical Filter

Apply on the contract-level dedup of `sandbox.t2_fact_overdue_portfolio_timeline`:

```sql
collectable_delinquent_portfolio = TRUE
```

with contract-grain deduplication:

```sql
ROW_NUMBER() OVER (
  PARTITION BY sk_contract, dt_reference
  ORDER BY CASE WHEN dt_invoice_paid IS NULL THEN 1 ELSE 2 END, dt_invoice_paid DESC
) = 1
```

### Nuances

- **Two formula families coexist per stage** — "share of total population" (this entity's official Catalog definition) vs. "step-to-step conversion" (a related, separately-charted analytical view). Confirm which one a given Superset chart or ad hoc query uses before comparing numbers across sources.
- **Cumulative-to-date vs. discrete-daily join pattern**: most funnel/spin charts join contact logs and negotiation data with `dt_occurrence <= dt_reference` within the same month (cumulative month-to-date); at least one chart on the same dashboard ("Collections Daily CPC over Open Contracts") instead matches the log's own business-day to the contract's `business_day` (discrete daily). See `t2_overdue_portfolio_context.md` (Dos and Don'ts) for the full explanation.
- **Native cut dimensions confirmed for this entity**: `advisory` (a full parallel chart set exists per stage/Spin), `contract_status` (Active/Finished — "Status Contrato" filter), and `debtor_type` (Flow/Stock — "Estoque/Fluxo" filter). `segmentation` and aging buckets, documented as cuts on the parent T2 entity, were not observed in this dashboard's own chart titles and are not confirmed as native filters here specifically.
- Contact-log channel taxonomy (`action_description` mapping from raw `datalake_cyber.collection.action` codes) is documented in `t2_overdue_portfolio_context.md`.
- Rolling window convention: production charts commonly scope to a trailing ~7 month window.

## Dos and Don'ts

**Do:**
- Deduplicate `t2_fact_overdue_portfolio_timeline` to contract grain before computing any funnel or Spin metric.
- Confirm whether a chart uses the "share of total" or "step conversion" formula before comparing two sources.
- Use `advisory`, `contract_status`, or `debtor_type` as native cut dimensions for this entity.
- Cast `datalake_cyber.collection.id_contract_external` to `BIGINT` before joining on `sk_contract`.

**Don't:**
- Don't confuse this entity's "% Acordo" member (a contract-level conversion share) with the separate Colchão Effectiveness / Agreement Recovery entity (a currency recovery amount on a different, mutually-exclusive population).
- Don't treat `GRB` as a confirmed collection agency without validating it first.
- Don't mix the cumulative-to-date and discrete-daily join patterns when comparing two funnel charts.

## Golden Queries

**Funnel stage rates (Spin/Alô/CPC/Promessa/Acordo) as a share of the total contract population**, by business day. Validated in Trino (dry run).

```sql
SELECT
    date_trunc('day', CAST(dt_month_end AS TIMESTAMP)) AS dt_month_end,
    business_day,
    COUNT(DISTINCT sk_contract) AS qt_contratos,
    COUNT(DISTINCT CASE WHEN total_esforco > 0 THEN sk_contract END) * 1.0000 / COUNT(DISTINCT sk_contract) AS "% Acionado",
    COUNT(DISTINCT CASE WHEN total_alo > 0 THEN sk_contract END) * 1.0000 / COUNT(DISTINCT sk_contract) AS "% Alô",
    COUNT(DISTINCT CASE WHEN total_cpc > 0 THEN sk_contract END) * 1.0000 / COUNT(DISTINCT sk_contract) AS "% CPC",
    COUNT(DISTINCT CASE WHEN total_promessa > 0 THEN sk_contract END) * 1.0000 / COUNT(DISTINCT sk_contract) AS "% Promessa",
    COUNT(DISTINCT CASE WHEN total_acordo > 0 THEN sk_contract END) * 1.0000 / COUNT(DISTINCT sk_contract) AS "% Acordo"
FROM (
    WITH logs_data AS (
        SELECT
            CAST(id_contract_external AS BIGINT) AS sk_contract,
            CAST(esforco AS BIGINT) AS esforco, CAST(alo AS BIGINT) AS alo, CAST(cpc AS BIGINT) AS cpc,
            DATE(ts_occurrence) AS dt_occurrence, DATE(DATE_TRUNC('MONTH', ts_occurrence)) AS dt_month_occurrence
        FROM datalake_cyber.collection
        WHERE action_code_type = 'Ação'
          AND DATE(DATE_TRUNC('MONTH', ts_occurrence)) > date_add('month', -7, current_date)
    ),
    fact_negotiation_data AS (
        SELECT CAST(sk_contract AS BIGINT) AS sk_contract, origin_agreement, dt_promisse, dt_down_payment, dt_cancellation
        FROM dw_collection_recovery_quintoandar.fact_negotiation
    ),
    negotiation_flags AS (
        SELECT sk_contract, 1 AS promessa, 0 AS acordo, DATE(dt_promisse) AS dt_occurrence, DATE(DATE_TRUNC('MONTH', dt_promisse)) AS dt_month_occurrence
        FROM fact_negotiation_data
        WHERE (DATE(dt_promisse) <> DATE(dt_cancellation) OR dt_cancellation IS NULL) AND (origin_agreement <> 'Boletagem' OR origin_agreement IS NULL)
        UNION ALL
        SELECT sk_contract, 0, 1, DATE(dt_down_payment), DATE(DATE_TRUNC('MONTH', dt_down_payment))
        FROM fact_negotiation_data
        WHERE dt_down_payment IS NOT NULL
    ),
    logs_totals AS (SELECT sk_contract, SUM(esforco) AS total_esforco, SUM(alo) AS total_alo, SUM(cpc) AS total_cpc, dt_occurrence, dt_month_occurrence FROM logs_data GROUP BY 1, 5, 6),
    negotiation_totals AS (SELECT sk_contract, SUM(promessa) AS total_promessa, SUM(acordo) AS total_acordo, dt_occurrence, dt_month_occurrence FROM negotiation_flags GROUP BY 1, 4, 5),
    contract_dedup AS (
        SELECT sk_contract, business_day, dt_reference, dt_month_start, dt_month_end,
            ROW_NUMBER() OVER (PARTITION BY sk_contract, dt_reference ORDER BY CASE WHEN dt_invoice_paid IS NULL THEN 1 ELSE 2 END, dt_invoice_paid DESC) AS rn
        FROM sandbox.t2_fact_overdue_portfolio_timeline
        WHERE collectable_delinquent_portfolio = TRUE AND is_last_business_days = TRUE AND dt_month_start > date_add('month', -7, current_date)
    ),
    contract_base AS (SELECT sk_contract, business_day, dt_reference, dt_month_start, dt_month_end FROM contract_dedup WHERE rn = 1)
    SELECT
        c.sk_contract, c.business_day, c.dt_month_end,
        COALESCE(n.total_promessa, 0) AS total_promessa, COALESCE(n.total_acordo, 0) AS total_acordo,
        COALESCE(l.total_esforco, 0) AS total_esforco, COALESCE(l.total_alo, 0) AS total_alo, COALESCE(l.total_cpc, 0) AS total_cpc
    FROM contract_base c
    LEFT JOIN negotiation_totals n ON c.sk_contract = n.sk_contract AND n.dt_month_occurrence = c.dt_month_start AND n.dt_occurrence <= c.dt_reference
    LEFT JOIN logs_totals l ON c.sk_contract = l.sk_contract AND l.dt_month_occurrence = c.dt_month_start AND l.dt_occurrence <= c.dt_reference
) AS base
WHERE business_day = 10 -- replace with the desired MTD business-day lock
GROUP BY date_trunc('day', CAST(dt_month_end AS TIMESTAMP)), business_day
ORDER BY dt_month_end DESC
```

**Spin (contact intensity)**, by business day, trailing 7 months. Validated in Trino (dry run).

```sql
SELECT
    business_day,
    dt_month_end,
    SUM(total_esforco) * 1.000 / COUNT(DISTINCT sk_contract) / MAX(business_day) AS spin_geral
FROM (
    WITH logs_data AS (
        SELECT
            CAST(id_contract_external AS BIGINT) AS sk_contract,
            CAST(esforco AS BIGINT) AS esforco,
            DATE(ts_occurrence) AS dt_occurrence, DATE(DATE_TRUNC('MONTH', ts_occurrence)) AS dt_month_occurrence
        FROM datalake_cyber.collection
        WHERE action_code_type = 'Ação'
          AND DATE(DATE_TRUNC('MONTH', ts_occurrence)) > date_add('month', -7, current_date)
    ),
    logs_totals AS (SELECT sk_contract, SUM(esforco) AS total_esforco, dt_occurrence, dt_month_occurrence FROM logs_data GROUP BY 1, 3, 4),
    contract_dedup AS (
        SELECT sk_contract, business_day, dt_reference, dt_month_start, dt_month_end,
            ROW_NUMBER() OVER (PARTITION BY sk_contract, dt_reference ORDER BY CASE WHEN dt_invoice_paid IS NULL THEN 1 ELSE 2 END, dt_invoice_paid DESC) AS rn
        FROM sandbox.t2_fact_overdue_portfolio_timeline
        WHERE collectable_delinquent_portfolio = TRUE AND is_last_business_days = TRUE AND dt_month_start > date_add('month', -7, current_date)
    ),
    contract_base AS (SELECT sk_contract, business_day, dt_reference, dt_month_start, dt_month_end FROM contract_dedup WHERE rn = 1)
    SELECT c.sk_contract, c.business_day, c.dt_month_end, COALESCE(SUM(l.total_esforco), 0) AS total_esforco
    FROM contract_base c
    LEFT JOIN logs_totals l ON c.sk_contract = l.sk_contract AND l.dt_month_occurrence = c.dt_month_start AND l.dt_occurrence <= c.dt_reference
    GROUP BY 1, 2, 3
) AS base
GROUP BY business_day, dt_month_end
ORDER BY dt_month_end DESC, business_day DESC
```

## Superset Golden Assets

Dashboard **Ações de Cobrança** `[Fintech][P&P]` (`urn:li:dashboard:(superset,dashboard.2367)`, https://superset.apps.data-prd.habitat.zone/superset/dashboard/2367) — confirmed live via DataHub, 57 charts total. The core charts backing this entity's five Catalog metrics:

- **Contracts Actioned per Business Day (%)** — slice 32243 — `urn:li:chart:(superset,chart.32243)`
- **Successful Contacted Contracts per Business Day (%)** — slice 32244 — https://superset.data.quintoandar.com.br/explore/?slice_id=32244
- **Successful CPC Contracts per Business Day (%)** — slice 32245 — `urn:li:chart:(superset,chart.32245)`
- **Successful Promises Generated per Business Day (%)** — slice 32246 — `urn:li:chart:(superset,chart.32246)`
- **Successful Payment Negotiation per Business Day (%)** — slice 32247 — https://superset.data.quintoandar.com.br/explore/?slice_id=32247
- **Accumulated Spin per Business Day** — slice 33009 — `urn:li:chart:(superset,chart.33009)`

Per-`advisory` versions of the same five metrics exist as a parallel chart set (slices 33751, 33641, 33752, 33755, 33757, 33638). Step-conversion variants (a related but distinct formula — see Nuances) are slices 32302, 32303, 32307, 32304. **Not included** here: ~15 charts on the same dashboard are log-volume/audit/anomaly-detection monitoring for specific vendor integrations (e.g. "Audit MEETCALL Logs Vol...", "Audit GRB Logs Vol...", "Phones Call CPC Anomaly...") — those are data-quality/ops monitoring, not business metrics for this entity.
