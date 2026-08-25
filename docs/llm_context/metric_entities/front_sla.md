# Front SLA

## Ownership

**Data Owner:**

- [joao.mariani@quintoandar.com.br](mailto:joao.mariani@quintoandar.com.br)

**Data Steward:**

- [victor.sakai@quintoandar.com.br](mailto:victor.sakai@quintoandar.com.br)


## Overview

**Front SLA** is the official service-level indicator of the CX Front operation: the share of eligible inbound customer contacts that were answered fast enough, measured per day and split between the pre-contract and post-contract journeys. It is published as three component metrics — **SLA Chat**, **SLA Call** and **SLA Total** — computed over the segments perspective of `dw_bpo_performance.segments_perspective` (version v2).

The metric is not a simple "answered on time / answered" ratio. Two rules make the naive path wrong:

- Call is measured only over the population of legs that Twilio itself counts as an inbound Call segment (`is_twilio_sla_segment = TRUE`). `fact_customer_contacts` contains additional legs (reservation timeout, rejected, canceled) that Twilio does not count as segments; including them inflates the denominator.
- SLA Total is a volume-weighted ratio of Chat and Call, never the arithmetic mean of SLA Chat and SLA Call.

Abandonment and queue time for Call come from Twilio-reconciled fields (`is_abandoned_twilio`, `queue_time_twilio`), not from `calls.ends_in_abandon` and not from the ring-time column `queue_time`.

## Related Domain Entities

- Contact
- Department

## Catalog

| Metric | Type |
| :---- | :---- |
| SLA Chat | Health Metric |
| SLA Call | Health Metric |
| SLA Total | Health Metric |

## MBR

**Name** Post Contract
**Category** CS Quality

## Glossary and Synonyms

- **Front SLA**, **SLA Front**, **SLA do Front**, **SLA de atendimento** → this metric (the set of the three components below)
- **SLA Chat**, **SLA de Chat** → the Chat component
- **SLA Call**, **SLA de Call**, **SLA de voz** → the Call component
- **SLA Total**, **SLA geral**, **SLA consolidado** → the volume-weighted combination of Chat and Call
- **Volume elegível Chat** → `chat_eligible_volume` (Chat denominator)
- **Chat dentro do SLA** → `chat_within_sla` (Chat numerator)
- **Volume elegível Call** → `call_eligible_volume` (Call denominator)
- **Call dentro do SLA** → `call_within_sla` (Call numerator)
- **Pré-Contrato**, **Pré**, **PRE** → `contract_stage = 'pre_contract'`
- **Pós-Contrato**, **Pós**, **POS** → `contract_stage = 'post_contract'`
- **meta do SLA**, **meta de SLA**, **target do SLA**, **SLA target** → the 80% target described in "Targets and OKRs"

## Scope

**Included**:

- Channels: Chat (`twilio_channel IN ('Chat', 'chat5a')`) and Call (`twilio_channel = 'Call'`). `chat5a` is the in-app chat (`channel = 'chat' AND origin = 'in app'`).
- Direction: inbound only (`direction = 'inbound'`; the source rows also carry `refined_direction = 'INBOUND'`).
- Segment type / grain: `kind = 'Conversation'`. One row per `sk_interaction` (leg) of `dw_customer_support.fact_customer_contacts`. For Call, only the subset flagged by `is_twilio_sla_segment = TRUE` represents a Twilio segment.
- Queues (10) — business names, grouped by contract stage:

| Business queue name | Raw value in source | `contract_stage` |
| :---- | :---- | :---- |
| CX Pagamentos [FRONT] [POS] | `[AeC] CX Pagamentos [FRONT] [POS]` | `post_contract` |
| CX Rescisão [FRONT] [POS] | `[AeC] CX Rescisão [FRONT] [POS]` | `post_contract` |
| CX Mudança [FRONT] [POS] | `[AeC] CX Mudança [FRONT] [POS]` | `post_contract` |
| CX Reparos [FRONT] [POS] | `[AeC] CX Reparos [FRONT] [POS]` | `post_contract` |
| CX Ongoing [FRONT] [POS] | `[AeC] CX Ongoing [FRONT] [POS]` | `post_contract` |
| CX Propostas [FRONT] [PRE] | `[AeC] CX Propostas [FRONT] [PRE]` | `pre_contract` |
| CX Visitas [FRONT] [PRE] | `[AeC] CX Visitas [FRONT] [PRE]` | `pre_contract` |
| CX Parceiros [FRONT] [PRE] | `[AeC] CX Parceiros [FRONT] [PRE]` | `pre_contract` |
| Consultores imobiliários 5A | `[AeC] Consultores imobiliários 5A` | `pre_contract` |
| CX Parceiros Compra e Venda [FRONT] | `[AeC] CX Parceiros Compra e Venda [FRONT]` | `pre_contract` |

**Excluded**:

- Outbound contacts and any channel other than chat / call.
- Any queue outside the 10 listed above (back-office queues, non-Front queues, other vendors).
- For Call: legs whose `is_twilio_sla_segment = FALSE` — i.e. `reservation.timeout`, `reservation.rejected`, `reservation.canceled` legs, and the extra `fact_customer_contacts` rows of an abandoned task that are not the ranked segment row.
- For Call: abandoned segments with `queue_time_twilio <= 5` seconds (excluded from both numerator and denominator).
- For Chat: contacts where the per-team eligibility flag is not true (`per_team_flag`, from `fact_customer_contacts.is_per_team_task`).

## Calculation

All three components are computed over the same row population, differing only in the eligibility predicates.

```
Chat eligible   = COUNT(rows WHERE twilio_channel IN ('Chat','chat5a')
                                AND kind = 'Conversation'
                                AND direction = 'inbound'
                                AND per_team_flag IS TRUE)

Chat within SLA = COUNT(Chat eligible rows WHERE first_reply_time_twilio <= 90)

SLA Chat        = Chat within SLA / Chat eligible


Call answered   = COUNT(rows WHERE twilio_channel = 'Call'
                                AND kind = 'Conversation'
                                AND direction = 'inbound'
                                AND is_twilio_sla_segment IS TRUE
                                AND is_abandoned_twilio IS FALSE)

Call abandoned>5 = COUNT(rows WHERE twilio_channel = 'Call'
                                AND kind = 'Conversation'
                                AND direction = 'inbound'
                                AND is_twilio_sla_segment IS TRUE
                                AND is_abandoned_twilio IS TRUE
                                AND queue_time_twilio > 5)

Call eligible   = Call answered + Call abandoned>5

Call within SLA = COUNT(Call answered rows WHERE queue_time_twilio <= 60)

SLA Call        = Call within SLA / Call eligible


SLA Total       = (Chat within SLA + Call within SLA)
                  / (Chat eligible + Call eligible)
```

SLA Total is a volume-weighted ratio. It is not `(SLA Chat + SLA Call) / 2` and it is not the average of daily ratios.

Thresholds, in seconds: Chat first reply `<= 90`; Call queue time `<= 60` for the numerator; Call abandonment cutoff `> 5` for the denominator.

All denominators are wrapped in `NULLIF(..., 0)` in the source query, so a day with no eligible volume returns `NULL`, never a division error.

### Time Axis

The official business date is `dt_created`, defined in the source query as:

```sql
DATE(fcc.ts_task_created - INTERVAL '3' HOUR) AS dt_created
```

The daily aggregation applied on top of the dataset is `date_trunc('day', CAST(dt_created AS TIMESTAMP))`. The period window is applied upstream on `fcc.ts_task_created` against timezone-anchored instants:

```sql
fcc.ts_task_created >= from_iso8601_timestamp('YYYY-MM-DDT00:00:00-03:00')
AND fcc.ts_task_created <  from_iso8601_timestamp('YYYY-MM-DDT00:00:00-03:00')
```

Do not use as the analysis date: `ts_load` (`current_timestamp` at load time), `year` / `month` / `day` (partition columns derived from `dt_created`), `ts_reservation_created`, `response_date` or `dt_task_created`.

### Classification Dimension: Contract Stage

`contract_stage` is derived deterministically from the effective queue name of the row, using the 10-queue mapping in "Scope". Values: `pre_contract`, `post_contract`. Rows whose queue is outside the mapping are out of scope and must not appear in the result.

The effective queue name reproduces the source query's own queue predicate and differs by channel:

```sql
CASE
  WHEN channel = 'call'
    THEN COALESCE(seg_answered.queue_name_twilio,      -- reservation.accepted
                  seg_abandoned.queue_name_twilio,     -- task.canceled / task.system-deleted
                  seg_not_counted.queue_name_twilio,   -- timeout / rejected / canceled
                  dim_department.department)            -- fallback: raw department name
  ELSE dim_department.department                        -- chat
END AS queue_name_effective
```

In the published dataset this expression is materialized as `queue_name_twilio` (for Call it is the per-segment queue from `call_flex_events.task_queue_name`; for Chat it falls back to the raw `dim_department.department`). Both carry the raw naming convention, including the `[AeC] ` vendor prefix. The column `department` is the normalized name (the source query strips the `[AeC] ` prefix through an explicit `CASE` mapping over exactly these 10 queues). Match on both spellings to be safe.

Do not derive `contract_stage` from string heuristics such as `LIKE '%POS%'` / `LIKE '%PRE%'`, and do not use the source column `front_pre_pos` (see "Known Limitations" in Nuances below).

### Canonical Filter

Applied on the segments perspective (v2) rows:

```sql
-- population common to every component
channel IN ('chat', 'call')
AND direction = 'inbound'
AND kind = 'Conversation'
AND queue_name_effective IN (the 10 Front queues, raw or normalized spelling)
AND dt_created inside the analysis window

-- Chat component adds
AND twilio_channel IN ('Chat', 'chat5a')
AND LOWER(COALESCE(CAST(per_team_flag AS VARCHAR), 'false')) = 'true'

-- Call component adds
AND twilio_channel = 'Call'
AND LOWER(COALESCE(CAST(is_twilio_sla_segment AS VARCHAR), 'false')) = 'true'
```

The boolean predicates are written as `LOWER(COALESCE(CAST(<flag> AS VARCHAR), 'false')) = 'true'` in the official query; this is NULL-safe (`NULL` is treated as false) and must be preserved.

**Warning**: filtering Call only by `twilio_channel = 'Call' AND direction = 'inbound'` without `is_twilio_sla_segment` includes legs that Twilio does not count as segments (timeout / rejected / canceled reservations, plus the non-ranked `fact_customer_contacts` rows of abandoned tasks). This inflates `call_eligible_volume` and understates SLA Call.

**Warning**: filtering by `department` (normalized) only will miss rows whose queue value still carries the `[AeC] ` prefix, and vice-versa. Match both spellings.

### Nuances

#### Call Segment Reconciliation (Twilio)

Call segment population — built from `datalake_bigfone_twilio.call_flex_events` filtered by `direction = 'inbound' AND channel_type = 'voice'`:

- **answered segment** = one row per `reservation.accepted` (joined to `fact_customer_contacts` by `sk_reservation`);
- **abandoned segment** = one row per `task.canceled` / `task.system-deleted` event, ranked per `id_task` by `ts_created_utc, id_event`, matched to the ranked `fact_customer_contacts` row of the same `sk_task`;
- **not counted** = `reservation.timeout` / `reservation.rejected` / `reservation.canceled`.

`fcc_task_rank` predicate is **mandatory** — when ranking `fact_customer_contacts` rows of an abandoned task, rows whose `sk_reservation` was accepted in another queue must be excluded (`NOT EXISTS` against the answered-segment set). Without it, abandoned segments are lost and both `call_eligible_volume` and the abandoned>5s population shrink.

#### Queue Time Selection

Queue time selection is deterministic, not `MAX` — `queue_time_twilio` for answered segments comes from `datalake_twilio_flex_insights_clean.conversation_time_metrics` picked by `ROW_NUMBER()` ordered by `ABS(total_talk_time - call_flex_reservations.seconds_talk_time) ASC NULLS LAST`, then source priority (same reservation before task fallback), then `total_queue_time ASC`, then `total_talk_time ASC`. For abandoned segments it comes from the `conversation_time_metrics` row with `total_talk_time IS NULL`, ranked by `total_queue_time DESC`.

#### `conversation_time_metrics` Keys

`id_segment` is actually the Task SID (`WT...`), and `dt_created` is 100% NULL in that table.

#### Department Deduplication

`dim_department` must be deduplicated — `dw_customer_support.dim_department` contains `sk_department` values with more than one row, and the pipeline joins that dimension five times. Use a `ROW_NUMBER() OVER (PARTITION BY sk_department ORDER BY department) = 1` CTE in place of the raw table, otherwise rows fan out and every volume is overstated.

#### Chat Has No Segment Reconciliation

Chat is untouched by the Call reconciliation — the Chat component depends only on `per_team_flag`, `first_reply_time`, `origin`, `channel`, `direction` and `dt_created`. There is no Chat equivalent of `is_twilio_sla_segment`; `per_team_flag` is the only documented eligibility gate for Chat, and its business rule is not described in the source query.

#### No Weights or External Parameters

There is no GSheet or lookup table involved; the only parameters are the period bounds, the queue list and the second thresholds (90 / 60 / 5).

#### Data Sources and Joins

Published dataset: `dw_bpo_performance.segments_perspective` (segments perspective, v2 — "08" dataset).

Tables actually required to reproduce the SLA:

| Table | Role in the SLA | Join key |
| :---- | :---- | :---- |
| `dw_customer_support.fact_customer_contacts` | Base grain (one row per `sk_interaction`); source of `channel`, `origin`, `direction`, `is_per_team_task`, `first_reply_time`, `ts_task_created`, `sk_task`, `sk_reservation`, `sk_department` | — (base) |
| `datalake_bigfone_twilio.call_flex_events` | Official Call segment population, per-segment queue name, abandonment events | `id_reservation = fcc.sk_reservation`; `id_task = fcc.sk_task` |
| `datalake_bigfone_twilio.call_flex_reservations` | `seconds_talk_time`, used only as the tie-breaker key when selecting queue time | `id_reservation` |
| `datalake_twilio_flex_insights_clean.conversation_time_metrics` | `total_queue_time`, `total_talk_time`, `first_reply_time` | `id_reservation`, and `id_segment` (= Task SID) `= fcc.sk_task` |
| `dw_customer_support.dim_department` (deduplicated) | Queue / department name, team, area | `sk_department = fcc.sk_department` |

`fact_customer_contacts` and `dim_department` are documented in the **Contact** and **Department** domain entities respectively — see those files for the general schema. The Twilio-side tables (`call_flex_events`, `call_flex_reservations`, `conversation_time_metrics`) are not yet covered by any domain entity in this repo; see "Known Limitations" below.

Tables present in the full v2 dataset but not used by any SLA field — safe to drop from an SLA-only query: `dw_support_journey.fact_services`, `dw_customer_support.dim_ticket`, `dim_analyst`, `dim_taxonomy`, `fact_ivr_interactions`, `dw_satisfaction_rating.fact_answer`, `fact_ticket_csat`, `datalake_satisfaction_rating.satisfaction_answers`, `datalake_chatbot.sessions`, `datalake_customer_support.calls` (the latter feeds only the ring-time column `queue_time`).

Partition predicates in the source query: `call_flex_events.year`, `call_flex_reservations.year`, `conversation_time_metrics.year + month`. They are hardcoded to the analyzed period and must be adapted whenever the window changes.

#### Field Glossary

Fields materialized on `dw_bpo_performance.segments_perspective` that are specific to the Twilio reconciliation layer of this metric (not already covered by the Contact / Department business entities):

| Field | Type | Description |
| :---- | :---- | :---- |
| `dt_created` | date | Official business date. `DATE(fcc.ts_task_created - INTERVAL '3' HOUR)`. |
| `twilio_channel` | varchar | `'Call'` when `channel = 'call'`; `'chat5a'` when `channel = 'chat' AND origin = 'in app'`; `'Chat'` for any other chat. |
| `kind` | varchar | Constant `'Conversation'` in this dataset. Kept in the filters for fidelity with the official query. |
| `direction` | varchar | Contact direction from `fact_customer_contacts`. SLA uses `'inbound'`. |
| `per_team_flag` | boolean | Chat eligibility flag. Comes from `fact_customer_contacts.is_per_team_task`. Chat rows only enter the SLA when this is true. |
| `first_reply_time_twilio` | double (seconds) | `COALESCE(CAST(fcc.first_reply_time AS DOUBLE), qt_answered.first_reply_time, ctm.first_reply_time)`. Chat SLA threshold: `<= 90`. |
| `is_twilio_sla_segment` | boolean | `TRUE` only for the rows Twilio counts as an inbound Call segment: answered (`reservation.accepted` matched by `sk_reservation`) or abandoned (`task.canceled` / `task.system-deleted` matched by `sk_task` with `fcc_rank = seg_rank`). Mandatory filter for the Call component. |
| `is_abandoned_twilio` | boolean | `TRUE` when the row matches a `task.canceled` / `task.system-deleted` Twilio event. Reconciled replacement for `calls.ends_in_abandon`. |
| `queue_time_twilio` | double (seconds) | Twilio queue time, deterministically selected (see "Queue Time Selection" above). Call SLA thresholds: `<= 60` (numerator), `> 5` (abandoned rows kept in the denominator). |
| `queue_name_twilio` | varchar | Per-segment queue name from `call_flex_events.task_queue_name`, falling back to the raw `dim_department.department`. Raw naming, includes the `[AeC] ` prefix. |
| `department` | varchar | Normalized queue name — the raw value with the `[AeC] ` prefix removed, via an explicit `CASE` covering the 10 Front queues. |
| `segment_outcome_twilio` | varchar | `'answered'`, `'abandoned'` or `NULL` (leg not counted as a segment). |
| `segment_source_event` | varchar | Originating Twilio event: `reservation.accepted`, `task.canceled`, `task.system-deleted`, `reservation.timeout`, `reservation.rejected`, `reservation.canceled`. Explains why a leg is not a segment. |
| `queue_time` | double (seconds) | Ring time, **not** queue time (`COALESCE(queue_time_calc, tm_fix.total_queue_time)`). Never use it for SLA. |
| `reservation_outcome` | varchar | `answered` / `abandoned` / `timeout` / `rejected` / `canceled`, per leg. |
| `front_pre_pos` | varchar | Legacy 'Pré' / 'Pós' classification derived from `dim_department.team`. **Not** the SLA classification — see "Known Limitations" below. |
| `ts_load` | timestamp | Load timestamp (`current_timestamp`). Technical field, never a business date. |
| `is_segment_grain_unavailable` | boolean | Constant `TRUE`: Twilio's official `segment_id` / `segment_order` are not reproducible in this dataset. |

#### Known Limitations and Interpretation Rules

- **`front_pre_pos` is not `contract_stage`.** The source query derives `front_pre_pos` from `dim_department.team`, classifying the teams Visits, Propostas, Moving, CX Partners, CX Compra e Venda, CIQ as 'Pré' and Repairs/Ongoing Front, Payments, Offboarding Front as 'Pós', with `NULL` for anything else. This conflicts with the official queue scope of this metric: `CX Mudança [FRONT] [POS]` is a post-contract queue while its team (Moving) is classified as 'Pré'. Always use the queue-based `contract_stage` defined in "Classification Dimension" above.
- **Twilio segment grain is not fully reproducible.** `is_segment_grain_unavailable` is constant `TRUE`: Twilio's official `segment_id` and `segment_order` do not exist in this pipeline. `segment_order_proxy` is an approximation and must not be treated as the Twilio segment order.
- **Residual queue-time divergence.** The deterministic selection of `queue_time_twilio` does not reconcile 100% of the rows against Twilio; a small residual of divergent queue times remains. Interpret SLA Call as a very close reproduction of the Twilio number, not as an exact identity.
- **Hardcoded partitions.** `call_flex_events`, `call_flex_reservations` and `conversation_time_metrics` are read with fixed `year` (and `month` for the latter). Any analysis crossing months or years requires widening these predicates, otherwise queue times and abandonment flags silently go missing for the uncovered periods.
- **Single-queue parameterization in the source.** The reference query is written for one `queue_name` at a time (the parameter is a single scalar and drives both the final `WHERE` and the ring-time CTE). The canonical version in this document generalizes it to the 10-queue Front scope; do not reintroduce a single-queue filter.
- **Vendor prefix.** Only the `[AeC] ` prefix is documented, through the explicit normalization mapping of the 10 queues. If the operation changes vendor or a queue is renamed, Validation check 4 will surface the unmapped value and the mapping must be updated.
- **Null time metrics.** Rows with `first_reply_time_twilio IS NULL` or `queue_time_twilio IS NULL` stay in the denominator (the eligibility predicates do not test for `NULL`) but can never satisfy the `<= 90` / `<= 60` conditions, so they always count as outside the SLA. Use Validation check 6 to size this effect before explaining a drop.
- **`kind` is a constant.** `kind = 'Conversation'` is a literal in this dataset, so that predicate never filters anything. It is kept for fidelity with the official query.
- **Figures inside the source query comments are point validations.** Counts such as the segment totals reported for a single day and a single queue, or a single-day Chat percentage, document the reconciliation exercise of version v2. They are not business rules, targets or expected values, and must never be quoted as such.
- **The 80% target has no system source.** It is a business constant declared by the metric owners, not a value read from a table, GSheet or DataHub property. There is no tolerance band and no per-queue exception; any classification beyond "at or above 80%" / "below 80%" is not documented and must not be invented.
- **No MBR and no Superset asset are documented.** The reference sources do not state which Monthly Business Review consumes this metric, nor a canonical Superset dataset / dashboard URN. Those sections are intentionally absent from this document and should be added once the owners confirm them.

## Dos and Don'ts

**Do:**

- Compute SLA Total as `(chat_within_sla + call_within_sla) / (chat_eligible_volume + call_eligible_volume)`.
- Always filter Call with `is_twilio_sla_segment = TRUE`.
- Use `is_abandoned_twilio` for abandonment and `queue_time_twilio` for queue time.
- Keep abandoned Call segments with `queue_time_twilio > 5` in the Call denominator, and keep them out of the numerator.
- Use `dt_created` as the business date.
- Derive `contract_stage` from the explicit 10-queue mapping, matching both the raw (`[AeC] ...`) and the normalized queue spellings.
- Deduplicate `dim_department` by `sk_department` before joining.
- Wrap every denominator in `NULLIF(..., 0)`.
- Report `sla_chat`, `sla_call`, `sla_total` together with the four volume columns so the ratios are auditable.

**Don't:**

- Don't compute SLA Total as the arithmetic mean of SLA Chat and SLA Call, nor as the average of daily ratios.
- Don't include Call legs/events outside the official Twilio segment population (timeout, rejected, canceled reservations, or non-ranked rows of abandoned tasks).
- Don't use `calls.ends_in_abandon` or any other abandonment proxy while the reconciled flag `is_abandoned_twilio` exists.
- Don't use ring time (`queue_time`, `queue_time_calc`, `tm_fix.total_queue_time`) in place of `queue_time_twilio`.
- Don't use load or partition fields (`ts_load`, `year`, `month`, `day`) as the analysis date.
- Don't classify pre/post with `LIKE '%PRE%'` / `LIKE '%POS%'` or with `front_pre_pos`.
- Don't leave single-queue, single-day or validation-only filters in the canonical query (e.g. one `queue_name` parameter, or a fixed `2026-07-27` date).
- Don't quote figures from a point validation (single queue / single day) as business rules or as expected values.
- Don't drop the `NOT EXISTS` guard in the abandoned-task ranking CTE.
- Don't express the gap to target as a percentage variation — the gap between two percentages is stated in percentage points (p.p.).
- Don't evaluate target attainment for a period by averaging daily SLA values; recompute the ratio from the summed volumes of the period.
- Don't classify a day/queue against the target when the denominator is zero (the SLA is `NULL`, not 0%).

## Targets and OKRs

**Budget (Target)** — the Front SLA target is a flat 80%, applied by default to every one of the 10 Front queues and to both `contract_stage` values. It applies individually to each of the three components: `sla_chat`, `sla_call` and `sla_total`.

- **Source table:** none. The target is a fixed business constant, not stored in a lookup table in the reference sources. Use the literal `0.80` (or 80 when the metric is expressed in percent).
- **Filter key / metric name:** not applicable — the same value applies to every queue, stage and component.
- **Aliases / search terms:** PT-BR: meta, meta do SLA, target, target do SLA, 80%.
- **Caveat:** no tolerance documented — there is no tolerance band and no per-queue exception: a result below 80% is below target, a result at or above 80% is at target. Compare on the same grain the SLA was computed (day or period, per `contract_stage`, optionally per queue). Express the gap as `realized − 80%` in percentage points (p.p.), never as a percentage variation. For a period, recompute the ratio from the summed numerators and denominators of the period — do not average daily ratios. No OKR path is documented for this metric, so no quarterly/semester goal is defined here. Should a per-queue or per-period target ever be formalized in a table or GSheet, this section must be replaced by the lookup path and the constant removed.

## Golden Queries

Self-contained Trino query returning, per `dt_created` and `contract_stage`: `sla_chat`, `sla_call`, `sla_total`, `chat_eligible_volume`, `chat_within_sla`, `call_eligible_volume`, `call_within_sla`. It reproduces only the SLA-relevant slice of the segments perspective v2 pipeline (non-SLA joins removed; every deduplication and ranking guard preserved) and replaces the single-queue parameter of the source query with the official 10-queue scope plus the `contract_stage` mapping.

Fields to adapt: `params.start_ts` / `params.end_ts`, and the partition predicates `year` / `month` of `call_flex_events`, `call_flex_reservations` and `conversation_time_metrics`.

### SLA by Day and Contract Stage

```sql
WITH params AS (
    SELECT
        from_iso8601_timestamp('2026-07-01T00:00:00-03:00') AS start_ts,  -- ADAPT
        from_iso8601_timestamp('2026-08-01T00:00:00-03:00') AS end_ts     -- ADAPT
),

-- Official Front scope: raw name, normalized name and contract stage.
queue_scope AS (
    SELECT *
    FROM (VALUES
        ('[AeC] CX Pagamentos [FRONT] [POS]',         'CX Pagamentos [FRONT] [POS]',         'post_contract'),
        ('[AeC] CX Rescisão [FRONT] [POS]',           'CX Rescisão [FRONT] [POS]',           'post_contract'),
        ('[AeC] CX Mudança [FRONT] [POS]',            'CX Mudança [FRONT] [POS]',            'post_contract'),
        ('[AeC] CX Reparos [FRONT] [POS]',            'CX Reparos [FRONT] [POS]',            'post_contract'),
        ('[AeC] CX Ongoing [FRONT] [POS]',            'CX Ongoing [FRONT] [POS]',            'post_contract'),
        ('[AeC] CX Propostas [FRONT] [PRE]',          'CX Propostas [FRONT] [PRE]',          'pre_contract'),
        ('[AeC] CX Visitas [FRONT] [PRE]',            'CX Visitas [FRONT] [PRE]',            'pre_contract'),
        ('[AeC] CX Parceiros [FRONT] [PRE]',          'CX Parceiros [FRONT] [PRE]',          'pre_contract'),
        ('[AeC] Consultores imobiliários 5A',         'Consultores imobiliários 5A',         'pre_contract'),
        ('[AeC] CX Parceiros Compra e Venda [FRONT]', 'CX Parceiros Compra e Venda [FRONT]', 'pre_contract')
    ) AS t (queue_name_raw, queue_name, contract_stage)
),

base_fcc AS (
    SELECT fcc.*
    FROM dw_customer_support.fact_customer_contacts AS fcc
    CROSS JOIN params AS p
    WHERE fcc.ts_task_created >= p.start_ts
      AND fcc.ts_task_created <  p.end_ts
      AND fcc.channel IN ('chat', 'call')
      AND fcc.direction = 'inbound'
),

-- Twilio voice events: the official Call segment population.
flex_events AS (
    SELECT id_event, id_task, id_reservation, task_queue_name, event_type, reason, ts_created_utc
    FROM datalake_bigfone_twilio.call_flex_events
    WHERE year = 2026                 -- ADAPT
      AND direction    = 'inbound'
      AND channel_type = 'voice'
),

seg_answered AS (
    SELECT
        id_reservation,
        MAX(id_task)         AS id_task,
        MAX(task_queue_name) AS queue_name_twilio,
        MAX(event_type)      AS source_event
    FROM flex_events
    WHERE event_type = 'reservation.accepted'
    GROUP BY 1
),

seg_abandoned AS (
    SELECT
        id_event,
        id_task,
        task_queue_name AS queue_name_twilio,
        event_type      AS source_event,
        ROW_NUMBER() OVER (PARTITION BY id_task ORDER BY ts_created_utc, id_event) AS seg_rank
    FROM flex_events
    WHERE event_type IN ('task.canceled', 'task.system-deleted')
),

seg_not_counted AS (
    SELECT
        id_reservation,
        MAX(task_queue_name) AS queue_name_twilio,
        MAX(event_type)      AS source_event
    FROM flex_events
    WHERE event_type IN ('reservation.timeout', 'reservation.rejected', 'reservation.canceled')
      AND id_reservation IS NOT NULL
    GROUP BY 1
),

-- Talk time per reservation: tie-breaker key for queue time only.
flex_resv AS (
    SELECT id_reservation, MAX(seconds_talk_time) AS seconds_talk_time
    FROM datalake_bigfone_twilio.call_flex_reservations
    WHERE year = 2026                 -- ADAPT
    GROUP BY 1
),

-- id_segment is the Task SID (WT...) despite the name; dt_created is 100% NULL here.
ctm_raw AS (
    SELECT
        id_conversation,
        id_segment AS id_task,
        id_reservation,
        total_queue_time,
        total_talk_time,
        first_reply_time
    FROM datalake_twilio_flex_insights_clean.conversation_time_metrics
    WHERE year = 2026                 -- ADAPT
      AND month = 7                   -- ADAPT
),

qt_candidates AS (
    SELECT
        sa.id_reservation,
        1 AS src_priority,
        ABS(c.total_talk_time - fr.seconds_talk_time) AS talk_diff,
        c.total_queue_time,
        c.total_talk_time,
        c.first_reply_time
    FROM seg_answered AS sa
    JOIN ctm_raw        AS c  ON c.id_reservation  = sa.id_reservation
    LEFT JOIN flex_resv AS fr ON fr.id_reservation = sa.id_reservation

    UNION ALL

    SELECT
        sa.id_reservation,
        2 AS src_priority,
        ABS(c.total_talk_time - fr.seconds_talk_time) AS talk_diff,
        c.total_queue_time,
        c.total_talk_time,
        c.first_reply_time
    FROM seg_answered AS sa
    JOIN ctm_raw        AS c  ON c.id_task = sa.id_task AND c.total_talk_time IS NOT NULL
    LEFT JOIN flex_resv AS fr ON fr.id_reservation = sa.id_reservation
),

qt_answered AS (
    SELECT id_reservation, total_queue_time AS queue_time_twilio, first_reply_time
    FROM (
        SELECT
            id_reservation,
            total_queue_time,
            first_reply_time,
            ROW_NUMBER() OVER (
                PARTITION BY id_reservation
                ORDER BY talk_diff ASC NULLS LAST,
                         src_priority,
                         total_queue_time ASC,
                         total_talk_time ASC
            ) AS rn
        FROM qt_candidates
    ) t
    WHERE rn = 1
),

qt_abandoned AS (
    SELECT id_task, total_queue_time AS queue_time_twilio
    FROM (
        SELECT
            id_task,
            total_queue_time,
            ROW_NUMBER() OVER (PARTITION BY id_task ORDER BY total_queue_time DESC) AS rn
        FROM ctm_raw
        WHERE total_talk_time IS NULL
    ) t
    WHERE rn = 1
),

-- Chat fallback for queue time / first reply time (chat has no reservation in fcc).
ctm_by_reservation AS (
    SELECT
        id_reservation,
        MAX(total_queue_time) AS queue_time_twilio,
        MIN(first_reply_time) AS first_reply_time
    FROM ctm_raw
    WHERE id_reservation IS NOT NULL
    GROUP BY 1
),

-- MANDATORY: the NOT EXISTS guard prevents marking an accepted reservation
-- (in another queue) as the abandoned segment row.
fcc_task_rank AS (
    SELECT
        f.sk_interaction,
        f.sk_task,
        ROW_NUMBER() OVER (
            PARTITION BY f.sk_task
            ORDER BY CASE WHEN f.sk_reservation IS NULL THEN 0 ELSE 1 END,
                     f.ts_reservation_created NULLS FIRST,
                     f.sk_interaction
        ) AS fcc_rank
    FROM base_fcc AS f
    WHERE f.channel = 'call'
      AND f.direction = 'inbound'
      AND NOT EXISTS (
          SELECT 1 FROM seg_answered AS sa WHERE sa.id_reservation = f.sk_reservation
      )
),

-- dim_department has duplicated sk_department values: deduplicate or volumes fan out.
dim_department_dedup AS (
    SELECT *
    FROM (
        SELECT d.*, ROW_NUMBER() OVER (PARTITION BY d.sk_department ORDER BY d.department) AS rn_dep
        FROM dw_customer_support.dim_department AS d
    ) t
    WHERE rn_dep = 1
),

sla_rows AS (
    SELECT
        DATE(fcc.ts_task_created - INTERVAL '3' HOUR) AS dt_created,
        CASE
            WHEN fcc.channel = 'call'
                THEN COALESCE(san.queue_name_twilio, sab.queue_name_twilio,
                              snc.queue_name_twilio, dd.department)
            ELSE dd.department
        END AS queue_name_effective,
        CASE
            WHEN fcc.channel = 'call'                           THEN 'Call'
            WHEN fcc.channel = 'chat' AND fcc.origin = 'in app' THEN 'chat5a'
            WHEN fcc.channel = 'chat'                           THEN 'Chat'
            ELSE fcc.channel
        END AS twilio_channel,
        CAST('Conversation' AS VARCHAR) AS kind,
        fcc.direction,
        fcc.is_per_team_task AS per_team_flag,
        COALESCE(CAST(fcc.first_reply_time AS DOUBLE), qa.first_reply_time, ctmr.first_reply_time)
            AS first_reply_time_twilio,
        CASE WHEN sab.id_event IS NOT NULL THEN TRUE ELSE FALSE END AS is_abandoned_twilio,
        CASE
            WHEN san.id_reservation IS NOT NULL THEN TRUE
            WHEN sab.id_event IS NOT NULL AND ftr.fcc_rank = sab.seg_rank THEN TRUE
            ELSE FALSE
        END AS is_twilio_sla_segment,
        CASE
            WHEN san.id_reservation IS NOT NULL THEN qa.queue_time_twilio
            WHEN sab.id_event       IS NOT NULL THEN qb.queue_time_twilio
            ELSE COALESCE(ctmr.queue_time_twilio, qb2.queue_time_twilio)
        END AS queue_time_twilio
    FROM base_fcc AS fcc
    LEFT JOIN dim_department_dedup AS dd   ON dd.sk_department  = fcc.sk_department
    LEFT JOIN seg_answered         AS san ON san.id_reservation = fcc.sk_reservation
    LEFT JOIN seg_not_counted      AS snc ON snc.id_reservation = fcc.sk_reservation
    LEFT JOIN fcc_task_rank        AS ftr ON ftr.sk_interaction = fcc.sk_interaction
    LEFT JOIN seg_abandoned        AS sab ON sab.id_task        = fcc.sk_task
                                        AND sab.seg_rank        = ftr.fcc_rank
    LEFT JOIN qt_answered          AS qa  ON qa.id_reservation  = fcc.sk_reservation
    LEFT JOIN qt_abandoned         AS qb  ON qb.id_task         = fcc.sk_task
    LEFT JOIN qt_abandoned         AS qb2 ON qb2.id_task        = fcc.sk_task
    LEFT JOIN ctm_by_reservation   AS ctmr ON ctmr.id_reservation = fcc.sk_reservation
),

sla_flags AS (
    SELECT
        r.dt_created,
        qs.contract_stage AS contract_stage,
        qs.queue_name AS queue_name,
        CASE
            WHEN r.twilio_channel IN ('Chat', 'chat5a')
             AND r.kind = 'Conversation'
             AND r.direction = 'inbound'
             AND LOWER(COALESCE(CAST(r.per_team_flag AS VARCHAR), 'false')) = 'true'
            THEN 1 ELSE 0
        END AS is_chat_eligible,
        CASE
            WHEN r.twilio_channel IN ('Chat', 'chat5a')
             AND r.kind = 'Conversation'
             AND r.direction = 'inbound'
             AND LOWER(COALESCE(CAST(r.per_team_flag AS VARCHAR), 'false')) = 'true'
             AND r.first_reply_time_twilio <= 90
            THEN 1 ELSE 0
        END AS is_chat_within_sla,
        CASE
            WHEN r.twilio_channel = 'Call'
             AND r.kind = 'Conversation'
             AND r.direction = 'inbound'
             AND LOWER(COALESCE(CAST(r.is_twilio_sla_segment AS VARCHAR), 'false')) = 'true'
             AND LOWER(COALESCE(CAST(r.is_abandoned_twilio AS VARCHAR), 'false')) = 'false'
            THEN 1
            WHEN r.twilio_channel = 'Call'
             AND r.kind = 'Conversation'
             AND r.direction = 'inbound'
             AND LOWER(COALESCE(CAST(r.is_twilio_sla_segment AS VARCHAR), 'false')) = 'true'
             AND LOWER(COALESCE(CAST(r.is_abandoned_twilio AS VARCHAR), 'false')) = 'true'
             AND r.queue_time_twilio > 5
            THEN 1 ELSE 0
        END AS is_call_eligible,
        CASE
            WHEN r.twilio_channel = 'Call'
             AND r.kind = 'Conversation'
             AND r.direction = 'inbound'
             AND LOWER(COALESCE(CAST(r.is_twilio_sla_segment AS VARCHAR), 'false')) = 'true'
             AND LOWER(COALESCE(CAST(r.is_abandoned_twilio AS VARCHAR), 'false')) = 'false'
             AND r.queue_time_twilio <= 60
            THEN 1 ELSE 0
        END AS is_call_within_sla
    FROM sla_rows AS r
    JOIN queue_scope AS qs
      ON r.queue_name_effective IN (qs.queue_name_raw, qs.queue_name)
)

SELECT
    dt_created,
    contract_stage,
    CAST(SUM(is_chat_within_sla) AS DOUBLE)
        / NULLIF(SUM(is_chat_eligible), 0) AS sla_chat,
    CAST(SUM(is_call_within_sla) AS DOUBLE)
        / NULLIF(SUM(is_call_eligible), 0) AS sla_call,
    CAST(SUM(is_chat_within_sla) + SUM(is_call_within_sla) AS DOUBLE)
        / NULLIF(SUM(is_chat_eligible) + SUM(is_call_eligible), 0) AS sla_total,
    SUM(is_chat_eligible)   AS chat_eligible_volume,
    SUM(is_chat_within_sla) AS chat_within_sla,
    SUM(is_call_eligible)   AS call_eligible_volume,
    SUM(is_call_within_sla) AS call_within_sla
FROM sla_flags
GROUP BY 1, 2
ORDER BY 1, 2
```

### Queue Breakdown

Same pipeline; replace only the final `SELECT` to break the result down by queue inside each contract stage. Aggregate the volumes, never the ratios, when rolling queues up.

```sql
SELECT
    dt_created,
    contract_stage,
    queue_name,
    CAST(SUM(is_chat_within_sla) AS DOUBLE)
        / NULLIF(SUM(is_chat_eligible), 0) AS sla_chat,
    CAST(SUM(is_call_within_sla) AS DOUBLE)
        / NULLIF(SUM(is_call_eligible), 0) AS sla_call,
    CAST(SUM(is_chat_within_sla) + SUM(is_call_within_sla) AS DOUBLE)
        / NULLIF(SUM(is_chat_eligible) + SUM(is_call_eligible), 0) AS sla_total,
    SUM(is_chat_eligible)   AS chat_eligible_volume,
    SUM(is_chat_within_sla) AS chat_within_sla,
    SUM(is_call_eligible)   AS call_eligible_volume,
    SUM(is_call_within_sla) AS call_within_sla
FROM sla_flags
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3
```

### Realized vs 80% Target

Same pipeline; replace only the final `SELECT`. Aggregates the whole period (drop `dt_created` from the grain), recomputing each ratio from the summed volumes, and reports the gap to target in percentage points. Change the grain by adding `dt_created` and/or `queue_name` to both the `SELECT` and the `GROUP BY`.

```sql
SELECT
    contract_stage,
    metric,
    realized,
    0.80 AS target,
    ROUND((realized - 0.80) * 100, 2) AS diff_pp,
    CASE
        WHEN realized IS NULL     THEN 'no eligible volume'
        WHEN realized >= 0.80     THEN 'at target'
        ELSE 'below target'
    END AS classification,
    eligible_volume,
    within_sla
FROM (
    SELECT
        contract_stage,
        metric,
        CAST(within_sla AS DOUBLE) / NULLIF(eligible_volume, 0) AS realized,
        eligible_volume,
        within_sla
    FROM (
        SELECT
            contract_stage,
            SUM(is_chat_eligible)   AS chat_eligible_volume,
            SUM(is_chat_within_sla) AS chat_within_sla,
            SUM(is_call_eligible)   AS call_eligible_volume,
            SUM(is_call_within_sla) AS call_within_sla
        FROM sla_flags
        GROUP BY 1
    ) agg
    CROSS JOIN UNNEST (
        ARRAY['sla_chat', 'sla_call', 'sla_total'],
        ARRAY[agg.chat_within_sla,
              agg.call_within_sla,
              agg.chat_within_sla + agg.call_within_sla],
        ARRAY[agg.chat_eligible_volume,
              agg.call_eligible_volume,
              agg.chat_eligible_volume + agg.call_eligible_volume]
    ) AS u (metric, within_sla, eligible_volume)
) t
ORDER BY contract_stage, metric
```

### Validation

Each check reuses the CTE stack of the Golden Query — replace only the final `SELECT`.

#### 1. Eligible and within-SLA volumes, and the containment invariant

`chat_within_sla <= chat_eligible_volume` and `call_within_sla <= call_eligible_volume` must hold for every day and stage; the query must return zero rows.

```sql
SELECT dt_created, contract_stage,
       SUM(is_chat_eligible) AS chat_eligible_volume,
       SUM(is_chat_within_sla) AS chat_within_sla,
       SUM(is_call_eligible) AS call_eligible_volume,
       SUM(is_call_within_sla) AS call_within_sla
FROM sla_flags
GROUP BY 1, 2
HAVING SUM(is_chat_within_sla) > SUM(is_chat_eligible)
    OR SUM(is_call_within_sla) > SUM(is_call_eligible)
```

#### 2. Non-zero denominators

Lists every day/stage whose Chat, Call or Total denominator is zero — those cells return `NULL` and must not be read as 0%.

```sql
SELECT dt_created, contract_stage,
       SUM(is_chat_eligible) AS chat_eligible_volume,
       SUM(is_call_eligible) AS call_eligible_volume,
       SUM(is_chat_eligible) + SUM(is_call_eligible) AS total_eligible_volume
FROM sla_flags
GROUP BY 1, 2
HAVING SUM(is_chat_eligible) = 0
    OR SUM(is_call_eligible) = 0
    OR SUM(is_chat_eligible) + SUM(is_call_eligible) = 0
```

#### 3. Pre / post separation

Expected: exactly 10 queues, 5 per stage, each queue in a single stage, and no `NULL` stage.

```sql
SELECT contract_stage,
       COUNT(DISTINCT queue_name) AS queues,
       ARRAY_AGG(DISTINCT queue_name ORDER BY queue_name) AS queue_list,
       SUM(is_chat_eligible) + SUM(is_call_eligible) AS total_eligible_volume
FROM sla_flags
GROUP BY 1
ORDER BY 1
```

#### 4. Scope leakage

Lists queue values inside the period that were not matched by `queue_scope`. Use it to catch new vendor prefixes or renamed queues before trusting the result — run it against `sla_rows`.

```sql
SELECT r.queue_name_effective, COUNT(*) AS rows_out_of_scope
FROM sla_rows AS r
LEFT JOIN queue_scope AS qs
  ON r.queue_name_effective IN (qs.queue_name_raw, qs.queue_name)
WHERE qs.contract_stage IS NULL
GROUP BY 1
ORDER BY 2 DESC
```

#### 5. Total is weighted, not averaged

Shows the correct `sla_total` next to the naive arithmetic mean; the two columns must not be interchanged, and any report where they match is a coincidence, not a validation.

```sql
SELECT dt_created, contract_stage,
       CAST(SUM(is_chat_within_sla) + SUM(is_call_within_sla) AS DOUBLE)
         / NULLIF(SUM(is_chat_eligible) + SUM(is_call_eligible), 0) AS sla_total_weighted,
       (CAST(SUM(is_chat_within_sla) AS DOUBLE) / NULLIF(SUM(is_chat_eligible), 0)
        + CAST(SUM(is_call_within_sla) AS DOUBLE) / NULLIF(SUM(is_call_eligible), 0)) / 2
         AS sla_total_naive_do_not_use
FROM sla_flags
GROUP BY 1, 2
ORDER BY 1, 2
```

#### 6. Call population composition

Splits the Call denominator into answered and abandoned>5s, and exposes abandoned segments with `queue_time_twilio <= 5` (excluded from the metric by design) — run it against `sla_rows` joined to `queue_scope`.

```sql
SELECT r.dt_created, qs.contract_stage,
       COUNT_IF(NOT r.is_abandoned_twilio)                              AS call_answered,
       COUNT_IF(r.is_abandoned_twilio AND r.queue_time_twilio > 5)      AS call_abandoned_gt5,
       COUNT_IF(r.is_abandoned_twilio AND r.queue_time_twilio <= 5)     AS call_abandoned_le5_excluded,
       COUNT_IF(r.queue_time_twilio IS NULL)                            AS call_queue_time_null
FROM sla_rows AS r
JOIN queue_scope AS qs
  ON r.queue_name_effective IN (qs.queue_name_raw, qs.queue_name)
WHERE r.twilio_channel = 'Call'
  AND r.direction = 'inbound'
  AND r.is_twilio_sla_segment
GROUP BY 1, 2
ORDER BY 1, 2
```
