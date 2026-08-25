# Ticket Rate Front - Pós Contrato

## Ownership

**Data Owner:**
- marina.gondim@quintoandar.com.br

**Data Steward:**
- barbara.borges@quintoandar.com.br

## Overview

**Ticket Rate Front - Pós Contrato** is the ratio between Front Office support segment volume (call + chat) in the billable Post Contract queues and the total stock of active For Rent contracts at the end of the reference month. It measures how much support demand the active rental book generates per contract, not per ticket created — using **answered, inbound segments only** (`sk_interaction`, deduplicated the same way for both channels, `origin NOT IN ('outbound')`). A call transferred between analysts produces one `sk_interaction` row per leg — each leg counts as its own segment by design; this is the official, business-confirmed rule, even though it means a single real phone call can contribute more than one unit to the call cut. Do not "fix" this by switching to `sk_session` for calls (see Nuances) — that was tried and explicitly rejected in favor of segment counting. Excluding outbound-origin calls (agent-initiated callbacks, ~12% of call volume) is what makes the call cut match the reference report — chat has no outbound rows, which is why chat matched from the start.

**Exists exclusively for For Rent Brazil.** The numerator (`fact_customer_contacts` / `dim_department`) has no country column at all — the billable queues are Brazil-only operations by construction, so no filter is needed or possible there. The denominator (`sandbox.summary_table_fr`) is the only side with country granularity, mixing Brazil (`BR`), Mexico (`MX`), and an unclassified `NULL` `country_code` — the canonical filter below restricts it to `country_code = 'BR'` so the whole metric stays Brazil-only end to end.

## Related Domain Entities

- Contact
- Department
- Ticket

## Catalog

| Metric | Type |
| :---- | :---- |
| Ticket Rate Front - Pós Contrato | Health Metric |

## MBR

**Name** Post Contract
**Category** Resolution Effectiveness

## Glossary and Synonyms

- **Ticket Rate Front - Pós Contrato** → official name of this metric (call + chat combined)
- **Ticket Rate**, **Rate Total**, **Taxa de Tickets Pós Contrato** → this same metric
- **Ticket Rate Front - Pós Contrato (Call)**, **Ticket Rate Front - Pós Contrato (Chat)** → single-channel cuts of the same metric — same denominator and same queue scope, numerator restricted to one channel

## Scope

**Included**: Front Office, answered, **inbound** contacts (`channel IN ('call', 'chat')`, `is_interaction_answered = TRUE`, `origin NOT IN ('outbound')`) handled in the **"Filas Faturáveis" (billable queues)** list — the business-maintained scope for this metric — in `dw_customer_support.dim_department.department`:

- `[AeC] CX Mudança [FRONT] [POS]`
- `[AeC] CX Ongoing [FRONT] [POS]`
- `[AeC] CX Pagamentos [FRONT] [POS]`
- `[AeC] CX Reparos [FRONT] [POS]`
- `CX Mudança [FRONT] [POS]`
- `CX Pagamentos [FRONT] [POS]`
- `CX Reparos [FRONT] [POS]`
- `CX Ongoing [FRONT] [POS]`
- `OPS COBRANÇA ATIVO [POS]`
- `[WH] Alteração de dados bancários [Front]`

**Excluded**:

- Unanswered contacts (`is_interaction_answered = FALSE`) — the metric counts resolved support demand only.
- Outbound-origin contacts (`origin = 'outbound'`) — agent-initiated callbacks, ~12% of raw call volume in the billable queues; chat has no outbound rows.
- `email` and any other channel besides `call`/`chat` (these queues also receive email contacts, which are out of scope for this metric).
- Back Office queues/departments (`front_or_back = 'back'`).
- Raw Twilio task/reservation counts (`datalake_bigfone_twilio.call_flex_reservations`, `dw_bpo_performance.twilio_chat_aht`) — these are unit-of-service counts (one call can have multiple reservations from transfers; one chat session can have multiple tasks) and **overcount** versus the deduplicated interaction grain used here.
- `sandbox.journey_post_contract` contract counts as a denominator source — this table's "ongoing" population (~102K contracts in Jun/2026) is a narrow subset, not the full active book (~358K in Jun/2026); do not use it for this metric.
- **Known scope nuance**: `CX Mudança [FRONT] [POS]` (both variants) is tagged `journey_step = 'Onboarding'` in `dim_department`, while the rest of the list is `journey_step = 'Ongoing'`, and `[WH] Alteração de dados bancários [Front]` is tagged `channel = 'Ticket Group'` (not `'Twilio'`) in `dim_department` — it is still part of the billable queue list even though it is not a Twilio-routed queue. The list mixes journey stages and routing systems by explicit business definition — do not "fix" this by narrowing it unless asked.

## Calculation

Counting raw ticket/task rows from Twilio (reservations/tasks, not `fact_customer_contacts` segments) over-inflates the numerator, and using `sandbox.journey_post_contract` for the denominator understates the contract base by roughly 3.5x. The correct calculation is:

```
Ticket Rate Front - Pós Contrato = ROUND((Calls + Chats) / Active_Rental_Contracts_EOM, 2)
```

where:
- `Calls` = `COUNT(DISTINCT sk_interaction)` from `dw_customer_support.fact_customer_contacts` where `channel = 'call'`.
- `Chats` = `COUNT(DISTINCT sk_interaction)` from the same table where `channel = 'chat'`.
- Both use the **same dedup column** (`sk_interaction` — "segments") and are scoped to the billable queue list above, to the reference month, to `is_interaction_answered = TRUE`, and to `origin NOT IN ('outbound')`.
- `Active_Rental_Contracts_EOM` = the `Ongoing Rental` metric value from `sandbox.summary_table_fr`, for `country_code = 'BR'`, on the exact last calendar day of the reference month (for the current, still-open month, use the most recent available date instead — see Fallback below).

**This metric is reported as a plain number rounded to 2 decimal places (e.g. `0.49`), never as a percentage (e.g. never `48.74%`).** The primary, official value is always the call + chat combined total. Call-only and chat-only cuts may be derived on request using the same denominator and the same queue scope, restricting the numerator's `channel` filter to one value — round each cut to 2 decimals the same way.

### Canonical Filter

Apply on `dw_customer_support.fact_customer_contacts` joined to `dw_customer_support.dim_department`:

```sql
fc.channel IN ('call', 'chat')
AND fc.is_interaction_answered = TRUE
AND fc.origin NOT IN ('outbound')
AND dd.department IN (
    '[AeC] CX Mudança [FRONT] [POS]', '[AeC] CX Ongoing [FRONT] [POS]',
    '[AeC] CX Pagamentos [FRONT] [POS]', '[AeC] CX Reparos [FRONT] [POS]',
    'CX Mudança [FRONT] [POS]', 'CX Pagamentos [FRONT] [POS]', 'CX Reparos [FRONT] [POS]',
    'CX Ongoing [FRONT] [POS]', 'OPS COBRANÇA ATIVO [POS]', '[WH] Alteração de dados bancários [Front]'
)
-- then COUNT(DISTINCT sk_interaction), split by channel — same dedup column for call and chat
```

Apply on `sandbox.summary_table_fr` for the denominator:

```sql
metric_name = 'Ongoing Rental'
AND country_code = 'BR'
AND date = last_day_of_month(DATE '{reference_month}-01')
```

**Warning**: dropping `country_code = 'BR'` pulls in Mexico (`MX`, ~172 contracts/month) and an unclassified `NULL` bucket (~109–135 contracts/month) into the denominator — small in absolute terms but still incorrect for a BR-only support metric. Also, using any date other than the exact last calendar day of the month (e.g. the early-month snapshot in `dw_public_snapshot.dim_contract_snapshot`, which lands on the 2nd/5th of the month, not the 30th/31st) will not match this metric's definition — that table is only useful as a rough cross-check, not as the denominator source. Forgetting `is_interaction_answered = TRUE` and, especially, `origin NOT IN ('outbound')` on the numerator inflates the call cut by roughly 12% (agent-initiated callbacks) — this is the reason an earlier version of this document matched the reference report on chat but not on call (see Nuances).

### Nuances

`sandbox.summary_table_fr` is the denominator source for active contract stock. It is a
general metrics mart keyed by `metric_name`, `city_group`, `country_code`, `business_context`,
and `date` — **not currently registered in DataHub**; this document is the source of truth
for its grain and filters until it is catalogued. Budget / OKR / target values for this
metric live on the same table under this metric's own `metric_name` — see
`## Targets and OKRs`.

| Column | Description |
| :----- | :---------- |
| `metric_name` | Metric identifier; use `'Ongoing Rental'` for the active-contract stock |
| `date` | Daily grain — reference date for the metric value (not a load/partition date) |
| `country_code` | `'BR'`, `'MX'`, or `NULL` (unclassified) — filter to `'BR'` only |
| `city_group` | One row per city cluster; sum across all `city_group` values to get the national total |
| `act_numerator` / `act_denominator` | Raw actual numerator/denominator; for `'Ongoing Rental'`, `act_denominator = 1` per row, so `SUM(act_numerator)` is the contract count |

**Join key**: none — numerator and denominator come from different tables at different grains (interaction-level vs. daily contract-stock mart) and are combined only at the `ref_month` level. `fc.ts_task_created` is `TIMESTAMP WITH TIME ZONE` and `sandbox.summary_table_fr.date` is `DATE` — `CAST(fc.ts_task_created AS DATE)` before `DATE_TRUNC('month', ...)` on the numerator side; joining the raw timestamp truncation against the date truncation matches zero rows.

**Fallback**: for a **closed** month, `sandbox.summary_table_fr` had a value for `'Ongoing Rental'` on every tested month-end date (Apr–Jul 2026); if a future month-end date is missing, do not substitute an earlier/later date silently — flag it to the user. For the **current, still-open** month, there is no last-day-of-month row yet — use `MAX(date)` up to today instead (e.g. `date <= CURRENT_DATE`, take the latest available) and note in the answer that the value is a running/partial figure, not a closed-month one.

**Critical nuance — outbound calls**: `fc.origin` on `channel = 'call'` rows takes values `'inbound'` or `'outbound'` (agent-initiated callbacks) — about 12% of raw call volume in the billable queues is outbound (e.g. 9,218 of 73,842 in Jun/2026). Chat rows never have `origin = 'outbound'` (only `'in app'` / `'whatsapp'`, occasionally `NULL`). This is the actual reason an early version of this document only matched the reference report's chat cut and not its call cut: chat was implicitly inbound-only already, call was not. **`origin NOT IN ('outbound')` also drops rows where `origin IS NULL`** (standard SQL `NOT IN` behavior with NULL) — this is intentional here (the ~1 null-origin chat row per month is negligible) but worth knowing if `origin` coverage changes upstream.

**Considered and rejected — call by `sk_session`**: `dw_customer_support.fact_customer_contacts` is at a grain finer than "one real contact" for calls specifically — a call transferred between analysts produces multiple `sk_interaction` rows (one per leg) sharing the same `sk_session`. An earlier version of this document counted calls by `COUNT(DISTINCT sk_session)` to collapse those legs into one unit per real call, since that matched a specific reference report more closely for two test months (Jun/2026: 0.17; Jul/2026: 0.18). **This was explicitly reverted** — the official rule counts every leg as its own segment (`sk_interaction`) for both channels, per business decision. If a comparison report shows a noticeably lower call figure than this document's output, it is likely using the session-collapsed count instead of segments — that report's methodology, not this one, should be revisited.

## Dos and Don'ts

**Do:**

- Use `COUNT(DISTINCT sk_interaction)` from `fact_customer_contacts` for **both** the call and chat cuts — same dedup column, split only by `channel`; never raw rows from Twilio task/reservation tables.
- Filter both channels to `is_interaction_answered = TRUE` **and** `origin NOT IN ('outbound')`.
- Filter the denominator to `country_code = 'BR'` and the exact last calendar day of the reference month (or the latest available date for the current, open month).
- Sum `act_numerator` across all `city_group` rows for the denominator — there is no pre-aggregated national total row.
- Report every value (total and any channel cut) as a plain number rounded to 2 decimal places (`ROUND(..., 2)`).
- When asked for call-only or chat-only, reuse the same denominator and queue scope — only restrict `channel` (and keep the channel-specific dedup column) in the numerator.

**Don't:**

- Don't switch calls to `sk_session` to "collapse" transfer legs — that was tried and rejected; the official rule counts every leg as its own segment, same as chat.
- Don't forget the `origin NOT IN ('outbound')` filter — without it, the call cut runs ~12% too high (outbound/agent-initiated calls are out of scope).
- Don't use `sandbox.journey_post_contract` (`type_replicated`) for the denominator — it materially undercounts the active contract base.
- Don't use `datalake_bigfone_twilio.call_flex_reservations` or `dw_bpo_performance.twilio_chat_aht` as the numerator — they count reservations/tasks, not deduplicated interactions, and inflate the rate.
- Don't use `dw_public_snapshot.dim_contract_snapshot` as the denominator — it only has one snapshot per month, dated early in the month, not the last day.
- Don't drop the `country_code = 'BR'` filter on the denominator.
- Don't express any of these values as a percentage.
- Don't report a call-only or chat-only cut as if it were the official metric — always lead with the combined total unless the user explicitly asks for a channel breakdown.

## Targets and OKRs

**Budget (Target)** — annual commitment for Ticket Rate Front - Pós Contrato, on the same
mart as the denominator.

- **Source table:** `sandbox.summary_table_fr`
- **Filter key / metric name:** `metric_name` for **Ticket Rate Front - Pós Contrato** (confirm
  the exact string in the mart — distinct from `'Ongoing Rental'`)
- **Period grain:** daily (`date`)
- **Canonical scope filters:** `country_code = 'BR'`; sum across all `city_group` rows for
  the national value
- **Aliases / search terms:** orçamento ticket rate, budget ticket rate front pós contrato
- **Caveat:** confirm the budget column name from the mart schema — the mart is not registered
  in DataHub.

**OKR** — period OKR for the same metric, on the same mart rows.

- **Source table:** `sandbox.summary_table_fr`
- **Filter key / metric name:** same `metric_name` as Budget above
- **Period grain:** daily (`date`); align the reference `date` with the month used for the
  calculated actual
- **Canonical scope filters:** `country_code = 'BR'`; sum across `city_group` for national
- **Aliases / search terms:** meta ticket rate pós contrato, OKR ticket rate front
- **Caveat:** confirm the OKR column name from the mart schema; do not read goals from
  `'Ongoing Rental'` rows.

## Golden Queries

Computes Ticket Rate Front - Pós Contrato per month, as a plain number rounded to 2 decimals. The official value is `ticket_rate_front_pos_contrato` (call + chat combined); `ticket_rate_front_pos_contrato_call` and `ticket_rate_front_pos_contrato_chat` are the same metric cut by channel, included because they share the denominator and can be produced by the same query — lead with the combined total unless the user asks for the channel breakdown. The numerator CTE reproduces the interaction-count pattern documented in the `Contact` domain entity (unified call + chat via `fact_customer_contacts`); what is exclusive to this metric is the queue whitelist and the join to the `Ongoing Rental` denominator from `sandbox.summary_table_fr`. Call and chat use the **same dedup column** (`sk_interaction` — segments), split only by `channel`, and both exclude `origin = 'outbound'` and unanswered interactions. Reference values for Apr–Jul/2026: total 0.47 / 0.46 / 0.53 / 0.47; call 0.19 / 0.15 / 0.18 / 0.19; chat 0.28 / 0.31 / 0.35 / 0.28. Validated against a reference report for Jun/2026 (0.17 call) and Jul/2026 (0.18 call) — within 0.01, consistent with chat's residual gap.

```sql
WITH interactions AS (
    -- Front segment volume: answered, inbound only, same dedup column (sk_interaction) for both channels
    SELECT
        DATE_TRUNC('month', CAST(fc.ts_task_created AS DATE)) AS ref_month,   -- CAST to DATE: ts_task_created is TIMESTAMP WITH TIME ZONE, active_contracts.ref_month is DATE — join fails silently without this cast
        COUNT(DISTINCT CASE WHEN fc.channel = 'call' THEN fc.sk_interaction END) AS calls,
        COUNT(DISTINCT CASE WHEN fc.channel = 'chat' THEN fc.sk_interaction END) AS chats
    FROM dw_customer_support.fact_customer_contacts AS fc
    LEFT JOIN dw_customer_support.dim_department AS dd
        ON fc.sk_department = dd.sk_department
    WHERE dd.department IN (
        '[AeC] CX Mudança [FRONT] [POS]', '[AeC] CX Ongoing [FRONT] [POS]',
        '[AeC] CX Pagamentos [FRONT] [POS]', '[AeC] CX Reparos [FRONT] [POS]',
        'CX Mudança [FRONT] [POS]', 'CX Pagamentos [FRONT] [POS]', 'CX Reparos [FRONT] [POS]',
        'CX Ongoing [FRONT] [POS]', 'OPS COBRANÇA ATIVO [POS]', '[WH] Alteração de dados bancários [Front]'
    )
    AND fc.channel IN ('call', 'chat')
    AND fc.is_interaction_answered = TRUE
    AND fc.origin NOT IN ('outbound')
    AND fc.ts_task_created >= TIMESTAMP '2026-04-01 00:00:00'
    AND fc.ts_task_created < TIMESTAMP '2026-08-01 00:00:00'
    GROUP BY 1
),
active_contracts AS (
    -- Ongoing Rental stock, end-of-month snapshot, Brazil only
    SELECT
        DATE_TRUNC('month', date) AS ref_month,
        SUM(act_numerator) AS active_contracts
    FROM sandbox.summary_table_fr
    WHERE metric_name = 'Ongoing Rental'
      AND country_code = 'BR'
      AND date IN (DATE '2026-04-30', DATE '2026-05-31', DATE '2026-06-30', DATE '2026-07-31')
    GROUP BY 1
)
SELECT
    it.ref_month,
    ROUND(CAST(it.calls + it.chats AS DOUBLE) / ac.active_contracts, 2) AS ticket_rate_front_pos_contrato,
    ROUND(CAST(it.calls AS DOUBLE) / ac.active_contracts, 2) AS ticket_rate_front_pos_contrato_call,
    ROUND(CAST(it.chats AS DOUBLE) / ac.active_contracts, 2) AS ticket_rate_front_pos_contrato_chat
FROM interactions it
JOIN active_contracts ac
    ON ac.ref_month = it.ref_month
ORDER BY 1
```

