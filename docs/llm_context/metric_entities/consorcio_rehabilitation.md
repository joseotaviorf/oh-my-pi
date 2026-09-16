# Consórcio — Rehabilitation

## Ownership

**Data Owner:**
- conrado.fabri@quintoandar.com.br

**Data Steward:**
- conrado.fabri@quintoandar.com.br

## Overview

**Repescagem** is the reactivation motion of Consórcio: when a deal is **discarded** (the end of that deal's funnel) and it is **eligible**, it is enrolled in a messaging cadence (*régua*) that tries to recapture the customer. If the customer replies to any cadence message, a **new deal is created with `origin = 'repescagem'`**.

This metric entity is a **separate document from the Cohort View** because of one structural fact: the interesting properties of a repescagem deal live on the **previously discarded deal**, not on itself. The recaptured deal always shows `origin = 'repescagem'`, so its original acquisition channel, its discard stage, its discard aging and how many cadence triggers it received can only be read by **linking the recaptured deal back to the discarded one**. Conversion *of* repescados (once they exist as deals) is already covered by the Cohort View — what is exclusive here is the **discarded ↔ repescado linkage** and the cadence funnel built on it.

**A reply is not necessarily caused by the cadence.** A customer can re-engage on WhatsApp in the 2-day gap before the first trigger (`rehabilitation_trigger_count = '0'`) or long after leaving the cadence. Read recapture by cadence stage rather than assuming attribution.

**Source of truth:** `datalake_consorcio.deal` + `datalake_consorcio.deal_milestone`, joined 1:1 on `id_deal`. These tables already resolve the pipeline filter, the one-row-per-deal dedup, test/duplicate exclusion, origin/segment mapping, the funnel milestones and flags, and analyst attribution — none of that needs to be rebuilt in a query. Column names throughout this document are the **table** column names.

## Related Domain Entities

- Consórcio

## Catalog

| Metric                      | Type          |
| :-------------------------- | :------------ |
| Recapture Rate              | Health Metric |
| Cadence Entry Rate          | Health Metric |
| Discard Volume              | Health Metric |
| Recaptured Volume           | Health Metric |
| Non-Entry Reason            | Health Metric |
| Aging: discard → recapture  | Health Metric |
| Aging: creation → recapture | Health Metric |
| Triggers until recapture    | Health Metric |

## Glossary and Synonyms

Terms analysts use to ask for these metrics (the Portuguese keys are the search terms; the mapping is what they resolve to).

- **Repescagem**, **repescado**, **reativação** → this metric family
- **Régua**, **régua de repescagem**, **disparos** → the messaging cadence (`rehabilitation_trigger_count`)
- **Taxa de repescagem**, **% de repescados** → Recapture Rate
- **Entrou na régua**, **elegível** → `has_entered_rehabilitation = 'True'`
- **Motivo de saída**, **por que não entrou** or, if it entered **porquê saiu** → `rehabilitation_exit_reason`
- **Variante da régua**, **teste de régua** → `rehabilitation_variant`
- **Etapa de descarte** → the stage the deal was in when discarded (`discarded_from_stage`)
- **Pesquisa de descarte**, **feedback do descarte** → the `feedback_*` fields
- **Data de Saída da régua** - when the deal exited the rehabilitation flow → `ts_rehabilitation_exited`

## Scope

**Included**: all Consórcio deals that reached **`descarte`**, their eligibility outcome, their cadence journey, the **recaptured deals** (`origin = 'repescagem'`) linked back to them and the **conversion of a repescagem deal through the funnel when linking to a discarded deal**.

**Excluded**: deals never discarded; test deals and duplicates (already excluded upstream); To analyze conversion of recaptured deals without the need to link it to a discarded deal, use the Cohort View

## Calculation

The motion has three sequential populations. Every rate below is a ratio between two of them.

**1. Discarded** — deals that reached `descarte` (`ts_discarded IS NOT NULL`).
**2. Entered the cadence** — `has_entered_rehabilitation = 'True'`, stamped with `ts_rehabilitation_entered`, `rehabilitation_trigger_count = '0'`, and a `rehabilitation_variant`.
**3. Recaptured** — a **new deal** with `origin = 'repescagem'` linked back to the discarded deal.

**Eligibility (evaluated at discard, in this order):**

| Check                   | Fails when                                                   | Marking                                                                                                  |
| :---------------------- | :----------------------------------------------------------- | :------------------------------------------------------------------------------------------------------- |
| Discard reason eligible | reason not in the eligible list                              | `has_entered_rehabilitation = 'False'`, `rehabilitation_exit_reason = 'Motivo de descarte não elegível'` |
| No other active deal    | customer has another open deal                               | `has_entered_rehabilitation = 'False'`, `rehabilitation_exit_reason = 'Contém Deal Ativo'`               |
| No closed deal          | customer already bought, so they know the product end to end | `has_entered_rehabilitation = 'False'`, `rehabilitation_exit_reason = 'Possui Venda Fechada'`            |

Passing all three ⇒ `has_entered_rehabilitation = 'True'`. Where a future return lands — AI agent or human analyst — is decided by the routing rule below.

### Routing on return — AI agent or human analyst

The recaptured deal is assigned by **how far the discarded deal had progressed**, and the threshold depends on the track it came from:

| Track of the discarded deal | Routed to a human analyst when it had reached | Otherwise |
| :---- | :---- | :---- |
| `SIMULATOR IA` | **Simulação Aceita** (Simulation Accepted) | AI Agent |
| `SDR IA` | **Simulação** (Simulation Sent) | AI Agent |
| `SDR Humano` | **Simulação Aceita** — *rule added on 2026-09-02* | Simulator |

The logic is the same in all three: a customer who had already got far enough to be talking to a person goes back to a person; one who had not comes back to Conrado.

**`SDR Humano` changed on 2026-09-02.** Until that date, every rehabilitated `SDR Humano` deal was routed **straight to a human analyst**, with no check on progress. From 2026-09-02 it also tests whether the deal reached Simulação Aceita — if it did, human analyst; if not, Simulator. This is a **break in the series**: a `SDR Humano` recapture before and after that date is not the same population, so never compare routing mix, analyst load or recapture-by-route across the boundary without splitting the periods.

**Cadence:** the traditional variant fires the **first trigger 2 days after the discard**, incrementing `rehabilitation_trigger_count` (1 … 6). **Before each trigger** the active-deal and closed-deal checks run again as a guard — if the deal exits there, `ts_rehabilitation_exited` and `rehabilitation_exit_reason` (`Contém Deal Ativo` / `Possui Venda Fechada`) are stamped **but `has_entered_rehabilitation` stays `'True'`**. After the **6th trigger** (currently the last), the deal exits with `rehabilitation_exit_reason = 'Fim da régua'`.

**Metric formulas:**

```
Cadence Entry Rate         = #(has_entered_rehabilitation = 'True') / #(discarded)
Recapture Rate             = #(recaptured) / #(entered the cadence)
Recapture Rate by cadence stage
                           = #(recaptured with trigger_count = k) / #(reached trigger_count = k)
Discard Volume             = #(discarded)   -- overall, by discard stage, by creation→discard aging
Recaptured Volume          = #(recaptured)
Aging: discard → recapture = days between the discarded deal's discard timestamp and the recaptured deal's creation
Aging: creation → recapture = days between the discarded deal's creation and the recaptured deal's creation
```

Every discarded-deal attribute read on a recaptured deal — **original acquisition channel** (Meta, Google, …), **discard stage**, **discard aging**, **trigger count**, **variant**, qualifier answers, journey — comes from the **linked discarded deal**, never from the repescagem deal itself.

Deals that were discarded→recaptured→discarded→recaptured will have the last discard-deal `origin = 'repescagem'`. This is not a data error, it is expected as part of the flow.

### Feedback fields

`feedback_*` are the customer's answers to the **survey we send when a deal is discarded**, asking why it did not move forward:

| Column                        | Meaning                                              |
| :---------------------------- | :--------------------------------------------------- |
| `feedback_score`              | score given in the survey                            |
| `feedback_benefits`           | which benefits the customer valued (multi-select)    |
| `feedback_comment`            | free-text comment                                    |
| `is_feedback_contact_allowed` | whether the customer allows us to contact them again |

**The survey was introduced recently, so low volume is expected** — 78 answered discards in the Jun–Aug 2026 window. Report the base size alongside any feedback breakdown; the cuts are directional until volume builds up.

(The `qualifier_*` fields — the customer's answers to Conrado's qualifying questions — are documented in the Consórcio business entity.)

### Canonical Filter

The pipeline filter, the dedup to one row per deal and the test/duplicate exclusion are **already applied upstream** — do not re-add them.

```sql
-- discarded population (the spine): one row per deal that reached 'descarte'
WHERE ts_discarded IS NOT NULL

-- cadence population
AND has_entered_rehabilitation = 'True'        -- varchar, not boolean

-- recaptured population (the NEW deal)
WHERE lower(origin) = 'repescagem'

-- always scope the scan with the partitions
AND year = 2026 AND month IN (6,7,8)
```

**Warning**: reading a recaptured deal's **own** `origin` always returns `repescagem` — it says nothing about acquisition. Any channel, stage or aging cut for recaptured deals **must** come from the linked discarded deal. Equally, computing the recapture rate over *all discarded* deals instead of those that **entered the cadence** understates it — pick the denominator that matches the question.

### Nuances

- **Types (verified in Trino 2026-08-18):** `has_entered_rehabilitation`, `rehabilitation_trigger_count`, `rehabilitation_exit_reason` and `rehabilitation_variant` are **`varchar`** — compare the flag as the string `'True'` / `'False'`, and `CAST(rehabilitation_trigger_count AS INTEGER)` before any arithmetic. The timestamps are **real `timestamp(3) with time zone`** (`ts_rehabilitation_entered`, `ts_rehabilitation_exited`, `ts_last_template_sent`), so no string parsing is needed.
- **`has_entered_rehabilitation` stays `'True'` after a mid-cadence exit** — the exit is expressed by `ts_rehabilitation_exited` + `rehabilitation_exit_reason`, not by flipping the flag. To count "still in the cadence", check the exit timestamp, not the flag.
- **`rehabilitation_exit_reason` carries two different meanings.** With `has_entered_rehabilitation = 'False'` it is the *non-entry* reason (`Motivo de descarte não elegível`, `Contém Deal Ativo`, `Possui Venda Fechada`); with `'True'` it is the *exit* reason (`Contém Deal Ativo`, `Possui Venda Fechada`, `Fim da régua`). Always read it together with the flag.
- **`trigger_count = '0'` recaptures are real** — the customer re-engaged before the first trigger. They are recaptures, but not cadence-attributable. Report them as their own bucket.
- **Recapture can happen after the cadence ends** (long after the 6th trigger) — do not cap the recapture window at the cadence window.
- **`rehabilitation_variant`** identifies cadence A/B tests (content and timing). It is always a valid breakdown dimension and a confounder when comparing periods.
- **Counting flags — use them, do not `COUNT(*)`.** The grain is *one row per discard, plus one row per non-primary recapture*, so raw row counts are wrong:
  - `is_descarte_row = 1` marks the canonical discard row → **Discard Volume = `SUM(is_descarte_row)`**, which equals `COUNT(DISTINCT id_deal)`. Extra recaptures of the same discard reuse that `id_deal` with the flag at `0`, so they never inflate it.
  - `is_repescagem_primaria = 1` marks one recapture per discard → **discards that came back = `SUM(is_repescagem_primaria)`**, and **Recapture Rate = `SUM(is_repescagem_primaria) / SUM(is_descarte_row)`**.
  - Total recapture volume, counting every return including repeat ones, is `COUNT(DISTINCT id_deal_repescado)`.

**Linkage — the discarded ↔ recaptured join.** The key is the deal's phone number normalized to a `+` prefix, with `recaptured.ts_deal_created > discarded.ts_discarded`, resolved so that each recaptured deal is attributed to the customer's **most recent prior discard**.

- **This is a weak key and a known limitation.** Phone is the only identifier available today linking the two deals. Numbers reconcile in practice, but a customer changing number breaks the link and a shared number can mis-attribute. Treat linkage-derived cuts as directional.
- Attribution is resolved in two independent passes: per recaptured deal, the most recent discard before it; then per discard, the first subsequent recapture (the primary one). Recaptured deals with no attributable discard, and extra recaptures of the same discard, are kept as their own rows so no recapture volume is lost.
- `rehabilitation_type` classifies the recapture against the cadence variant (`Regua Legacy`, `Regua Descartes Nulos`, `Regua BAU`, `Regua 120d`, `Nenhuma`, `Outros`) — use it together with `trigger_count` to separate cadence-driven from organic returns.

## Dos and Don'ts

**Do:**

- Read every recaptured-deal attribute (channel, discard stage, aging, triggers, variant, qualifier, feedback) from the **linked discarded deal**.
- State which denominator a recapture rate uses — **discarded**, **entered the cadence**, or **reached trigger k**.
- Use `SUM(is_descarte_row)` and `SUM(is_repescagem_primaria)` for volumes and rates; never `COUNT(*)`.
- Compare the varchar flags as strings and `CAST` `rehabilitation_trigger_count` before arithmetic.
- Break the recapture rate by **trigger count** (including the `'0'` bucket) to separate cadence-driven from organic returns.
- Report the base size when cutting by `feedback_*`, which is still low volume.

**Don't:**

- Don't use a recaptured deal's own `origin` as its acquisition channel — it is always `repescagem`.
- Don't treat `has_entered_rehabilitation = 'True'` as "currently in the cadence" — check `ts_rehabilitation_exited`.
- Don't read `rehabilitation_exit_reason` without the flag — the same value means non-entry or exit depending on it.
- Don't assume every recapture was caused by the cadence, and don't cap recapture at the cadence window.
- Don't compute the funnel conversion of the recaptured deal here — that is the Cohort View.

## Golden Queries

Every query below is self-contained: it builds the discarded ↔ recaptured linkage directly from `datalake_consorcio.deal` + `datalake_consorcio.deal_milestone`. Adjust the partition filter to the window you need.

### Query 1 — Repescagem base (canonical)

One row per discarded deal (the spine) with its eligibility and cadence properties and the primary recapture attached when there is one, plus rows for recaptured deals that have no attributable discard and for extra recaptures of the same discard. The two counting flags make volumes and rates unambiguous.

```sql
WITH deals AS (
    SELECT
        d.id_deal,
        d.origin,
        d.discard_reason,
        d.dt_created,
        d.ts_deal_created,
        d.deal_amount,
        d.qualifier_goal,
        d.feedback_score,
        d.feedback_benefits,
        d.feedback_comment,
        d.is_feedback_contact_allowed,
        d.has_entered_rehabilitation,
        d.rehabilitation_exit_reason,
        d.rehabilitation_variant,
        d.rehabilitation_trigger_count,
        d.ts_rehabilitation_entered,
        d.ts_rehabilitation_exited,
        m.ts_discarded,
        m.discarded_from_stage,
        m.is_closed_deal,
        CASE WHEN starts_with(d.phone_number, '+') THEN d.phone_number
             ELSE '+' || d.phone_number END AS phone_key      -- linkage key
    FROM datalake_consorcio.deal d
    INNER JOIN datalake_consorcio.deal_milestone m ON m.id_deal = d.id_deal
    WHERE d.year = 2026 AND d.month IN (6,7,8)                -- scope the scan
),
discarded AS (
    SELECT * FROM deals WHERE ts_discarded IS NOT NULL
),
recaptured AS (
    SELECT * FROM deals WHERE lower(origin) = 'repescagem'
),
-- Attribution: per recaptured deal, the most recent discard before it (rn_rec = 1);
-- then per discard, the order of its recaptures (rn_disc = 1 is the primary one).
attribution AS (
    SELECT
        id_deal_recaptured,
        matched_discard_id,
        CASE WHEN matched_discard_id IS NULL THEN 1
             ELSE row_number() OVER (PARTITION BY matched_discard_id ORDER BY ts_recaptured_created ASC)
        END AS rn_disc
    FROM (
        SELECT
            r.id_deal          AS id_deal_recaptured,
            r.ts_deal_created  AS ts_recaptured_created,
            dsc.id_deal        AS matched_discard_id,
            row_number() OVER (PARTITION BY r.id_deal ORDER BY dsc.ts_discarded DESC) AS rn_rec
        FROM recaptured r
        LEFT JOIN discarded dsc
               ON dsc.phone_key = r.phone_key
              AND dsc.ts_discarded < r.ts_deal_created
    ) t
    WHERE rn_rec = 1
)
-- Spine: every discard, with its primary recapture when there is one.
SELECT
    dsc.id_deal,
    dsc.origin,
    dsc.discard_reason,
    dsc.discarded_from_stage,
    dsc.ts_discarded,
    dsc.dt_created                                   AS dt_discard_created,
    dsc.has_entered_rehabilitation,
    dsc.rehabilitation_exit_reason,
    dsc.rehabilitation_variant,
    dsc.rehabilitation_trigger_count,
    dsc.ts_rehabilitation_entered,
    dsc.ts_rehabilitation_exited,
    dsc.qualifier_goal,
    dsc.feedback_score,
    dsc.feedback_benefits,
    dsc.feedback_comment,
    dsc.is_feedback_contact_allowed,
    r.id_deal                                        AS id_deal_repescado,
    r.ts_deal_created                                AS ts_recaptured_created,
    r.is_closed_deal                                 AS is_recaptured_closed_deal,
    date_diff('day', dsc.ts_discarded, r.ts_deal_created) AS days_discard_to_recapture,
    date_diff('day', dsc.dt_created, r.ts_deal_created)   AS days_creation_to_recapture,
    date_diff('day', dsc.dt_created, dsc.ts_discarded)    AS days_creation_to_discard,
    1                                                AS is_descarte_row,
    CASE WHEN r.id_deal IS NOT NULL THEN 1 ELSE 0 END AS is_repescagem_primaria
FROM discarded dsc
LEFT JOIN attribution a ON a.matched_discard_id = dsc.id_deal AND a.rn_disc = 1
LEFT JOIN recaptured  r ON r.id_deal = a.id_deal_recaptured

UNION ALL

-- Non-primary recaptures: no attributable discard, or an extra recapture of the same discard.
SELECT
    dsc.id_deal,
    dsc.origin,
    dsc.discard_reason,
    dsc.discarded_from_stage,
    dsc.ts_discarded,
    dsc.dt_created,
    dsc.has_entered_rehabilitation,
    dsc.rehabilitation_exit_reason,
    dsc.rehabilitation_variant,
    dsc.rehabilitation_trigger_count,
    dsc.ts_rehabilitation_entered,
    dsc.ts_rehabilitation_exited,
    dsc.qualifier_goal,
    dsc.feedback_score,
    dsc.feedback_benefits,
    dsc.feedback_comment,
    dsc.is_feedback_contact_allowed,
    r.id_deal,
    r.ts_deal_created,
    r.is_closed_deal,
    date_diff('day', dsc.ts_discarded, r.ts_deal_created),
    date_diff('day', dsc.dt_created, r.ts_deal_created),
    date_diff('day', dsc.dt_created, dsc.ts_discarded),
    0,
    0
FROM attribution a
JOIN recaptured r      ON r.id_deal   = a.id_deal_recaptured
LEFT JOIN discarded dsc ON dsc.id_deal = a.matched_discard_id
WHERE a.matched_discard_id IS NULL   -- recaptures with no attributable discard
   OR a.rn_disc > 1                  -- extra recaptures of the same discard
```

### Query 2 — Cadence funnel: entry rate, recapture rate, non-entry reasons, aging

Same base, aggregated by discard month, discard stage, acquisition channel and cadence variant. Drop any grouping column for a broader view.

```sql
WITH deals AS (
    SELECT
        d.id_deal, d.origin, d.discard_reason, d.dt_created, d.ts_deal_created,
        d.has_entered_rehabilitation, d.rehabilitation_exit_reason,
        d.rehabilitation_variant, d.rehabilitation_trigger_count,
        d.ts_rehabilitation_entered,
        m.ts_discarded, m.discarded_from_stage,
        CASE WHEN starts_with(d.phone_number, '+') THEN d.phone_number
             ELSE '+' || d.phone_number END AS phone_key
    FROM datalake_consorcio.deal d
    INNER JOIN datalake_consorcio.deal_milestone m ON m.id_deal = d.id_deal
    WHERE d.year = 2026 AND d.month IN (6,7,8)
),
discarded AS (SELECT * FROM deals WHERE ts_discarded IS NOT NULL),
recaptured AS (SELECT * FROM deals WHERE lower(origin) = 'repescagem'),
attribution AS (
    SELECT id_deal_recaptured, matched_discard_id,
        CASE WHEN matched_discard_id IS NULL THEN 1
             ELSE row_number() OVER (PARTITION BY matched_discard_id ORDER BY ts_recaptured_created ASC)
        END AS rn_disc
    FROM (
        SELECT r.id_deal AS id_deal_recaptured, r.ts_deal_created AS ts_recaptured_created,
               dsc.id_deal AS matched_discard_id,
               row_number() OVER (PARTITION BY r.id_deal ORDER BY dsc.ts_discarded DESC) AS rn_rec
        FROM recaptured r
        LEFT JOIN discarded dsc ON dsc.phone_key = r.phone_key
                               AND dsc.ts_discarded < r.ts_deal_created
    ) t WHERE rn_rec = 1
),
spine AS (
    SELECT
        dsc.*,
        r.id_deal                                             AS id_deal_repescado,
        date_diff('day', dsc.ts_discarded, r.ts_deal_created) AS days_discard_to_recapture,
        date_diff('day', dsc.dt_created, r.ts_deal_created)   AS days_creation_to_recapture,
        date_diff('day', dsc.dt_created, dsc.ts_discarded)    AS days_creation_to_discard
    FROM discarded dsc
    LEFT JOIN attribution a ON a.matched_discard_id = dsc.id_deal AND a.rn_disc = 1
    LEFT JOIN recaptured  r ON r.id_deal = a.id_deal_recaptured
)
SELECT
    date_trunc('month', ts_discarded)   AS discard_month,
    discarded_from_stage                AS discard_stage,
    origin                              AS acquisition_channel,
    rehabilitation_variant              AS variant,

    COUNT(*)                                                                        AS discards,
    SUM(CASE WHEN has_entered_rehabilitation = 'True' THEN 1 ELSE 0 END)            AS entered_cadence,
    SUM(CASE WHEN id_deal_repescado IS NOT NULL THEN 1 ELSE 0 END)                  AS recaptured,

    ROUND(100.0 * SUM(CASE WHEN has_entered_rehabilitation = 'True' THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 2)                                                 AS entry_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN id_deal_repescado IS NOT NULL THEN 1 ELSE 0 END)
          / NULLIF(SUM(CASE WHEN has_entered_rehabilitation = 'True' THEN 1 ELSE 0 END), 0), 2)
                                                                                    AS recapture_rate_pct,

    SUM(CASE WHEN has_entered_rehabilitation = 'False'
              AND rehabilitation_exit_reason = 'Motivo de descarte não elegível' THEN 1 ELSE 0 END) AS not_eligible_reason,
    SUM(CASE WHEN has_entered_rehabilitation = 'False'
              AND rehabilitation_exit_reason = 'Contém Deal Ativo' THEN 1 ELSE 0 END)              AS not_active_deal,
    SUM(CASE WHEN has_entered_rehabilitation = 'False'
              AND rehabilitation_exit_reason = 'Possui Venda Fechada' THEN 1 ELSE 0 END)           AS not_closed_deal,

    AVG(days_discard_to_recapture)   AS avg_days_discard_to_recapture,
    AVG(days_creation_to_recapture)  AS avg_days_creation_to_recapture,
    AVG(days_creation_to_discard)    AS avg_days_creation_to_discard,
    AVG(CASE WHEN id_deal_repescado IS NOT NULL
             THEN CAST(rehabilitation_trigger_count AS INTEGER) END) AS avg_triggers_until_recapture
FROM spine
GROUP BY 1, 2, 3, 4
ORDER BY 1 DESC, discards DESC
```

### Query 3 — Recapture rate by cadence stage (and by any discard-side dimension)

The `'0'` bucket separates organic returns from cadence-driven ones. Swap the `GROUP BY` for `qualifier_goal`, `discarded_from_stage`, `origin` or any combination to cut it differently.

```sql
WITH deals AS (
    SELECT
        d.id_deal, d.origin, d.dt_created, d.ts_deal_created,
        d.has_entered_rehabilitation, d.rehabilitation_trigger_count,
        d.qualifier_goal,
        m.ts_discarded, m.discarded_from_stage,
        CASE WHEN starts_with(d.phone_number, '+') THEN d.phone_number
             ELSE '+' || d.phone_number END AS phone_key
    FROM datalake_consorcio.deal d
    INNER JOIN datalake_consorcio.deal_milestone m ON m.id_deal = d.id_deal
    WHERE d.year = 2026 AND d.month IN (6,7,8)
),
discarded AS (SELECT * FROM deals WHERE ts_discarded IS NOT NULL),
recaptured AS (SELECT * FROM deals WHERE lower(origin) = 'repescagem'),
attribution AS (
    SELECT id_deal_recaptured, matched_discard_id,
        CASE WHEN matched_discard_id IS NULL THEN 1
             ELSE row_number() OVER (PARTITION BY matched_discard_id ORDER BY ts_recaptured_created ASC)
        END AS rn_disc
    FROM (
        SELECT r.id_deal AS id_deal_recaptured, r.ts_deal_created AS ts_recaptured_created,
               dsc.id_deal AS matched_discard_id,
               row_number() OVER (PARTITION BY r.id_deal ORDER BY dsc.ts_discarded DESC) AS rn_rec
        FROM recaptured r
        LEFT JOIN discarded dsc ON dsc.phone_key = r.phone_key
                               AND dsc.ts_discarded < r.ts_deal_created
    ) t WHERE rn_rec = 1
),
spine AS (
    SELECT dsc.*, r.id_deal AS id_deal_repescado
    FROM discarded dsc
    LEFT JOIN attribution a ON a.matched_discard_id = dsc.id_deal AND a.rn_disc = 1
    LEFT JOIN recaptured  r ON r.id_deal = a.id_deal_recaptured
)
SELECT
    CAST(rehabilitation_trigger_count AS INTEGER)                  AS triggers_received,
    discarded_from_stage                                           AS discard_stage,
    COUNT(*)                                                       AS reached_this_stage,
    SUM(CASE WHEN id_deal_repescado IS NOT NULL THEN 1 ELSE 0 END) AS recaptured,
    ROUND(100.0 * SUM(CASE WHEN id_deal_repescado IS NOT NULL THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 2)                                AS recapture_rate_pct
FROM spine
WHERE has_entered_rehabilitation = 'True'
GROUP BY 1, 2
ORDER BY 1, reached_this_stage DESC
```

> **Validation anchor (Jun–Aug 2026, verified 2026-08-18):** 111,055 distinct discards — exactly equal to `SUM(is_descarte_row)`, confirming the grain is intact — 29,850 distinct recaptured deals and 18,376 primary recaptures, i.e. a **16.5% recapture rate**; `qualifier_goal` present on 25,860 rows.

## Superset Golden Assets

- **Repescagem - Main Dataset [Consorcio][Fintech]** — a materialized Superset dataset with this linkage already built, for exploration in Superset. URN: `urn:li:dataset:(urn:li:dataPlatform:superset,21382,PROD)`
