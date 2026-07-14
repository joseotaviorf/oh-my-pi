# Journey PC

## Ownership

**Data Owner:**
- samia.lauar@quintoandar.com.br
- felipe.abreu@quintoandar.com.br

**Data Steward:**
- victor.prado@quintoandar.com.br

## Overview

**Journey PC** (post-contract journey mix) is the family of metrics that measure the **share of
For Rent client slots** that went through each **support-interaction category** during the
post-contract journey (**onboarding and ongoing only — offboarding is excluded**):

- **% Seamless clients** — client slots with **no** support interaction (no ticket, no chatbot)
- **% Digital clients** — client slots with **chatbot/self-service** interaction only (no ticket)
- **% Human Support clients** — client slots that opened **at least one support ticket**

These three metrics size the **universe** of clients in each interaction category. They are the
population counterpart to the satisfaction metrics **NPS Seamless / NPS Digital Sup / NPS Human
Support** in `metric_entities/nps_fr.md`: those measure how **satisfied** each group is, while
Journey PC measures how **big** each group is. (They are computed on different bases and grains —
NPS at NPS-answer grain over respondents, Journey PC at contract × role grain over the whole
base — so the two will not tie out one-to-one.)

The category is **mutually exclusive** and assigned per contract × role × journey stage × month,
by precedence: any ticket → `human`; else any chatbot → `digital`; else `seamless`.

**This metric exists for For Rent — it tracks the post-contract contract base (onboarding +
ongoing stages only).**

**Grain note**: one "**client slot**" = one `(sk_contract, contract_role)` pair. A For Rent
contract with both tenant (IQ) and landlord (PP) roles contributes **two** client slots and is
counted independently for each role. This is intentional and matches the official spreadsheet.

## Related Business Entities

- ticket
- chatbot_sessions

## MBR

- Post Contract

## Glossary and Synonyms

- **% Seamless clients**, **Seamless share**, **% clientes seamless** → share of client slots with `category = 'seamless'`
- **% Digital clients**, **% Digital Sup clients**, **% clientes digital** → share of client slots with `category = 'digital'`
- **% Human Support clients**, **% Human clients**, **% clientes human sup.** → share of client slots with `category = 'human'`
- **category** → support-interaction class of a contract occurrence: `seamless` / `digital` / `human` / `other`
- **type_replicated** → journey stage of the occurrence: `onboarding` / `ongoing` / `offboarding`
- **contract_role** → `tenant` (IQ) / `landlord` (PP)
- **client slot** → one `(sk_contract, contract_role)` pair; the unit of counting for Journey PC
- **Total Digital / Total Tickets / Total Ticket Chat / Call / Back** → interaction-**volume** metrics (sums of `count_*`, not client-slot counts — see Nuances)

## Scope

**Included**: For Rent contracts in `sandbox.journey_post_contract` — signed contracts, Brazil,
status `Ativo` / `Finalizado`, roles `tenant` and `landlord` (`dweller` is folded into
`tenant`). **Only journey stages `onboarding` and `ongoing` are included.** The base contains
occurrences from **2025-01-01 onward** (`dt_replicated >= '2025-01-01'`).

**Excluded**: non-Brazil contracts, canceled terminations, and contracts without a signature
(all already filtered out during materialization), and **`type_replicated = 'offboarding'`** —
offboarding is intentionally excluded from both the Journey PC numerator and denominator.

## Calculation

The three metrics share the **same formula**, differing only by the `category` filtered. For a
given month (`month_replicated`):

```
% <category> clients = client_slots_in_category / client_slots_total × 100
```

where `client_slots_in_category` = distinct `(sk_contract, contract_role)` pairs restricted to
that `category` and `type_replicated NOT IN ('offboarding')`, and `client_slots_total` is the
**sum of the per-category client-slot counts** for the month (all categories, same stage
filter). The team computes it in the spreadsheet by first aggregating the base to one row per
`(month[, breakdown], category, contract_role)` with `E = COUNT(DISTINCT sk_contract)`, then
summing across roles:

```
numerator   = SUMIFS(E, month BETWEEN start AND end, category = 'seamless',
                        type_replicated NOT IN ('offboarding'))
denominator = SUMIFS(E, month BETWEEN start AND end,
                        type_replicated NOT IN ('offboarding'))   -- all categories
% Seamless  = numerator / denominator
```

Because a contract can appear in more than one occurrence within a month (e.g. `seamless` in
onboarding and `human` in ongoing), the denominator counts it **once per category × role** it
falls in — this is intentional and matches the official number. Since `other` does not occur in
practice (see Nuances), the three shares sum to ~100%.

### Canonical Filter

Read from `sandbox.journey_post_contract`. **Always apply `type_replicated NOT IN ('offboarding')`
to both numerator and denominator.** The table is otherwise already scoped to For Rent / Brazil /
signed contracts, so no extra campaign filter is required. Optional breakdowns: `type_replicated`
(onboarding vs. ongoing) and `contract_role` (IQ/PP). **Always bound the period with a
`month_replicated` filter** (the table's reporting/partition column) so the scan is limited —
never query it unbounded (data starts 2025-01).

**Warnings**:

- Never run an **unbounded** query — always include a `month_replicated` date bound (e.g. a rolling 24-month window) to prune the partition scan.
- Never restrict the **denominator** to a single category — the total must include all categories so the shares are comparable and sum to ~100%.
- Never compute the client shares from `SUM(count_*)` — those are interaction **volumes**, not client-slot counts (see Nuances).
- Never remove the `type_replicated NOT IN ('offboarding')` filter from either numerator or denominator — doing so changes the official definition and will not match the reference spreadsheet.
- **Warning**: `month_replicated` is `TIMESTAMP WITH TIME ZONE` — always do `CAST(month_replicated AS DATE)` (or equivalent) before comparing with `DATE` / `date_trunc` / `current_date`; comparing without the cast shifts the window by one month depending on the session timezone.

### Nuances

**Category derivation (precedence)** — assigned per occurrence in the source:

| Category | Rule (in order) | Metric |
| :---- | :---- | :---- |
| `human` | `count_human > 0` (any support ticket, incl. Salesforce cases) | % Human Support clients |
| `digital` | `count_human = 0` AND `count_digital > 0` (chatbot/walle only) | % Digital clients |
| `seamless` | `count_human = 0` AND `count_digital = 0` | % Seamless clients |
| `other` | none of the above | — (unreachable in practice) |

**Grain & deduplication** — one row per `(sk_contract, contract_role, month_replicated,
dt_replicated, type_replicated)`. The counting unit for Journey PC is the **client slot**:
`(sk_contract, contract_role)`. In SQL, achieve this by including `contract_role` in the CTE
`GROUP BY` and counting `COUNT(DISTINCT sk_contract)` within each role — the outer `SUM` then
naturally adds the two roles, giving the correct client-slot total. Never use `COUNT(*)` (a
contract has multiple stage occurrences within the same role in a month).

**`count_human` includes Salesforce cases** — in the source, `count_human` (and
`count_human_back`) already add Salesforce-platform cases on top of Zendesk/CX tickets.

**Breakdowns** — the same table supports cutting by `type_replicated` (onboarding vs. ongoing),
`contract_role` (IQ/PP), and `category`. When you add a breakdown, the denominator is taken
**within** that breakdown level. The `type_replicated NOT IN ('offboarding')` filter always
applies regardless of the breakdown chosen.

**IQ / PP mapping** — `contract_role = 'tenant'` → IQ; `contract_role = 'landlord'` → PP.

**Interaction-volume metrics** (sums, not client-slot counts) — also available in the same table:

| Metric | Expression |
| :---- | :---- |
| Total Digital | `SUM(count_digital)` |
| Total Tickets (Human) | `SUM(count_human)` |
| Total Ticket Chat | `SUM(count_human_chat)` |
| Total Ticket Call | `SUM(count_human_call)` |
| Total Ticket Back | `SUM(count_human_back)` |

**Relationship to the NPS Seamless family** — same conceptual taxonomy
(`seamless` / `digital` / `human`) as `seamless_ticket_type` in `metric_entities/nps_fr.md`, but
computed over the full contract base at contract × role grain rather than over NPS respondents at
answer grain. Use Journey PC for **population size**, NPS for **satisfaction** of each group; do
not expect the counts to match.

## Dos and Don'ts

**Do:**

- Count client slots by including `contract_role` in the CTE `GROUP BY` and using `COUNT(DISTINCT sk_contract)` within each role; the outer `SUM` across roles gives the correct client-slot total.
- Always apply `type_replicated NOT IN ('offboarding')` to both numerator and denominator.
- Always bound the query by `month_replicated` (e.g. a rolling 24-month window) to prune the scan — never query the table unbounded.
- Keep **all** categories in the denominator (`seamless` + `digital` + `human` + `other`).
- Break down by `type_replicated` (onboarding / ongoing) and/or `contract_role` (IQ = `tenant`, PP = `landlord`) when asked.
- Use `SUM(count_*)` **only** for the interaction-volume metrics (Total Digital / Tickets / Chat / Call / Back).

**Don't:**

- Don't compute the client shares from `SUM(count_digital)` / `SUM(count_human)` — those are interaction volumes, not client-slot counts.
- Don't filter the denominator to a single category.
- Don't include `type_replicated = 'offboarding'` in Journey PC calculations — it is intentionally excluded.
- Don't collapse `contract_role` before the CTE aggregation — doing so loses the IQ/PP split and undercounts client slots.
- Don't expect these shares to equal the NPS Seamless / Digital Sup / Human Support respondent counts in `nps_fr.md`.
- Don't query the table without a `month_replicated` date bound (unbounded scans over all history).
- Don't assume data before 2025-01.

## Golden Queries

The base table `sandbox.journey_post_contract` is at one row per contract occurrence
(`sk_contract` × stage × role × month). Aggregate distinct contracts per
`(month, category, contract_role)` — excluding offboarding — and take the share over the month
total. Including `contract_role` in the CTE `GROUP BY` ensures that IQ and PP are counted as
separate client slots, matching the official spreadsheet. Every query below is **bounded by
`month_replicated`** (a rolling 24-month window) — keep a date bound on `month_replicated` in any
adaptation so the scan is pruned; adjust the window as needed.

### Query 1 — % Seamless / Digital / Human Support clients by month

```sql
WITH contract_category AS (
    SELECT
        month_replicated        AS ref_month,
        category,
        contract_role,                              -- keep role in CTE to count IQ + PP separately
        COUNT(DISTINCT sk_contract) AS contracts
    FROM sandbox.journey_post_contract
    WHERE type_replicated NOT IN ('offboarding')    -- offboarding excluded from the official definition
      AND CAST(month_replicated AS DATE) >= date_trunc('month', date_add('month', -24, current_date))  -- date/partition bound: last 24 months (CAST: month_replicated is TIMESTAMP WITH TIME ZONE)
      AND CAST(month_replicated AS DATE) <= date_trunc('month', current_date)
    GROUP BY 1, 2, 3
)
SELECT
    ref_month,
    ROUND(SUM(CASE WHEN category = 'seamless' THEN contracts END) * 100.0 / SUM(contracts), 1) AS pct_seamless_clients,
    ROUND(SUM(CASE WHEN category = 'digital'  THEN contracts END) * 100.0 / SUM(contracts), 1) AS pct_digital_clients,
    ROUND(SUM(CASE WHEN category = 'human'    THEN contracts END) * 100.0 / SUM(contracts), 1) AS pct_human_support_clients,
    SUM(contracts) AS total_client_slots   -- denominator: client slots (contract × role) per category, no offboarding
FROM contract_category
GROUP BY 1
ORDER BY 1
```

### Query 2 — Same shares, broken down by journey stage and IQ/PP

Add `type_replicated` and/or drop `contract_role` from the outer `SELECT` as needed. The
denominator is taken within each breakdown cell. The `NOT IN ('offboarding')` filter always
applies; when breaking down by stage, only `onboarding` and `ongoing` will appear.

> **Note (Query 1 vs. Query 2)**: this stage-level breakdown is deliberately different from the
> monthly headline in Query 1. A client slot that is, say, `seamless` in both onboarding and
> ongoing within the same month is counted **once** in Query 1 (the `DISTINCT` deduplicates
> across stages) but **once per stage** here. So the per-stage rows will **slightly exceed** the
> Query 1 total — this is expected. Use Query 2 to understand how volume distributes across
> stages, not to reconcile to the headline. If you present both together, state this explicitly
> to avoid confusing whoever consumes the data.

```sql
WITH contract_category AS (
    SELECT
        month_replicated        AS ref_month,
        type_replicated,
        contract_role,                              -- 'tenant' = IQ, 'landlord' = PP
        category,
        COUNT(DISTINCT sk_contract) AS contracts
    FROM sandbox.journey_post_contract
    WHERE type_replicated NOT IN ('offboarding')
      AND CAST(month_replicated AS DATE) >= date_trunc('month', date_add('month', -24, current_date))  -- date/partition bound: last 24 months (CAST: month_replicated is TIMESTAMP WITH TIME ZONE)
      AND CAST(month_replicated AS DATE) <= date_trunc('month', current_date)
    GROUP BY 1, 2, 3, 4
)
SELECT
    ref_month,
    type_replicated,
    contract_role,
    ROUND(SUM(CASE WHEN category = 'seamless' THEN contracts END) * 100.0 / SUM(contracts), 1) AS pct_seamless_clients,
    ROUND(SUM(CASE WHEN category = 'digital'  THEN contracts END) * 100.0 / SUM(contracts), 1) AS pct_digital_clients,
    ROUND(SUM(CASE WHEN category = 'human'    THEN contracts END) * 100.0 / SUM(contracts), 1) AS pct_human_support_clients,
    SUM(contracts) AS total_client_slots
FROM contract_category
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3
```

### Query 3 — Interaction-volume metrics

Volumes are plain sums of the `count_*` columns (not client-slot counts). The offboarding
exclusion is applied here too for consistency with Journey PC reporting, but is not strictly
required since these are raw interaction counts.

```sql
SELECT
    month_replicated AS ref_month,
    type_replicated,
    contract_role,
    SUM(count_digital)     AS total_digital,
    SUM(count_human)       AS total_tickets,      -- Zendesk/CX tickets + Salesforce cases
    SUM(count_human_chat)  AS total_ticket_chat,
    SUM(count_human_call)  AS total_ticket_call,
    SUM(count_human_back)  AS total_ticket_back
FROM sandbox.journey_post_contract
WHERE type_replicated NOT IN ('offboarding')
  AND CAST(month_replicated AS DATE) >= date_trunc('month', date_add('month', -24, current_date))  -- date/partition bound: last 24 months (CAST: month_replicated is TIMESTAMP WITH TIME ZONE)
  AND CAST(month_replicated AS DATE) <= date_trunc('month', current_date)
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3
```

## Superset Golden Assets

The dataset below was born as a **virtual dataset** (Superset) and **has already been
materialized into a sandbox table** (one row per `sk_contract` × stage × role × month) —
**consume the table directly**; the Superset URN remains only as the origin/documentation of the
logic (the SQL is exposed in DataHub).

- **Contact Journey PostContract v2 [Support and Services][Performance]** — canonical base for the post-contract journey mix (contract occurrences per journey stage, with per-occurrence `category` and the `count_*` interaction columns). **Materialized in `sandbox.journey_post_contract`** — consume the table directly for all three shares and the volume metrics. URN (origin): `urn:li:dataset:(urn:li:dataPlatform:superset,20941,PROD)` ([link](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:%28urn:li:dataPlatform:superset,20941,PROD%29/Columns)).
