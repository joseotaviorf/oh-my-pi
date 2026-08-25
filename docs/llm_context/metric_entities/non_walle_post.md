# % Non Wall-E (POST)

## Ownership

**Data Owner:**
- marina.gondim@quintoandar.com.br

**Data Steward:**
- barbara.borges@quintoandar.com.br

## Overview

**% Non Wall-E (POST)** is the share of billable front-office chat contacts, restricted to the
**Post-contract** journey, that did **not** originate from the Wall-E chatbot. It measures how
much of the Post-contract support workload is still landing on humans (or other bots) instead of
being handled end-to-end by Wall-E.

The naive path — classifying Pre vs. Post by the department the contact currently sits in (or by
whichever department qualified it as "billable") — is wrong. A contact can be transferred across
multiple departments over its lifetime, and the department that made it "billable" is not
necessarily where the underlying session started. The correct segmentation looks at the **first
queue the session's own history touched** (via `is_first_interaction`), independent of whether
that first queue itself is one of the billable queues.

**Exists for the Front Office chat channel of the For Rent CX operation (CX + AeC BPO queues).
Wall-E origin (`is_wall_e`) is resolved from `datalake_chatbot.sessions` with a fixed lookback
from `2024-01-01` — the metric is validated for reporting periods on or after that date.
Do not apply this definition to call-channel volume or to the Pre-contract segment — those need
their own cut using the same mechanics but a different `segmento` filter.**

## Related Domain Entities

- Ticket
- Chatbot Sessions

## Catalog

| Metric | Type |
| :---- | :---- |
| % Non Wall-E (POST) | Health Metric |

## MBR

**Name** Post Contract
**Category** Resolution Effectiveness

## Glossary and Synonyms

- **Non Wall-E Post**, **Share Tickets Non Wall-E (Pós)**, **% Non Wall-E POST**, **não Wall-E
  pós-contrato** → this metric

## Scope

**Included**: `dw_customer_support.fact_customer_contacts` rows where `channel = 'chat'` and
`is_interaction_answered = TRUE`, whose **current** department (`sk_department` →
`dw_customer_support.dim_department.department`) is one of the 22 canonical "Contatos
Faturáveis" queues (see Canonical Filter), **and** whose underlying session's **first-ever**
department (via `is_first_interaction = TRUE`) classifies as **Post-contract** (see Nuances for
the keyword rules). Reporting periods (`ts_contact`) on or after **`2024-01-01`**.

**Excluded**:
- Call-channel contacts, unanswered interactions.
- Contacts whose current department is not one of the 22 canonical queues.
- Contacts whose session's first department classifies as **Pre-contract**.
- Reporting periods before **`2024-01-01`** — the Wall-E origin join does not load
  `datalake_chatbot.sessions` rows before that date; pre-2024 contacts cannot be reliably
  classified as Wall-E vs Non Wall-E under this definition.
- Contacts whose session has no identifiable first department at all (no `is_first_interaction`
  row found, or no valid session key) — these fall into an unclassified **"Outra origem"**
  bucket and must be reported separately, never folded into POST or PRE silently.
- Contacts whose `quinto_andar_phone_number` ends in the 8 digits `50285959` (matched via
  `LIKE '%50285959'` — this Trino version does not support `RIGHT()`; tolerant of DDD/
  country-code prefix variations, observed in production as the full number `551150285959`).
  This is a QuintoAndar-owned line used solely for document/image-upload support tied to
  *other* tickets, not a standalone contact, and must be dropped from **both** numerator and
  denominator (see Nuances).

## Calculation

The naive path — counting contacts by the department they currently sit in, or by "any billable
queue touched" — misattributes Pre vs. Post whenever a contact was transferred. The correct
calculation classifies each contact by the **first** department its underlying session ever
touched, then restricts to the Post-contract segment before computing the Wall-E share.

The correct calculation is:

```
% Non Wall-E (POST) = COUNT(DISTINCT sk_contact WHERE segmento = 'Pos' AND NOT is_wall_e)
                       / COUNT(DISTINCT sk_contact WHERE segmento = 'Pos')
```

where:

- **Universe** ("Contatos Faturáveis") = `fact_customer_contacts` rows with `channel = 'chat'`,
  `is_interaction_answered = TRUE`, current department in the 22-queue canonical list, **and**
  `quinto_andar_phone_number` not ending in `50285959` (see Nuances).
- **`segmento`** = derived once per underlying session from its **first** department
  (`is_first_interaction = TRUE`, earliest `ts_task_created`, one row per `session_key`) —
  classified `Pos` / `Pre` / `Outra_origem` per the keyword rules in Nuances. This is a
  session-level attribute, constant across all of that session's contacts.
- **`is_wall_e`** = `TRUE` when the contact's `session_key` matches a `datalake_chatbot.sessions`
  row with `bot = 'wall-e'` **and** `ts_created >= TIMESTAMP '2024-01-01 00:00:00'` (fixed
  lookback on the bot side — see Nuances; this is **not** a ticket-based join).
- **`session_key`** (contacts side) = `COALESCE(NULLIF(CAST(sk_session AS VARCHAR), '-1'),
  NULLIF(sk_support_session, '-1'))` — Sauron numeric ID first, SSS UUID as fallback.

### Canonical Filter

Apply on `dw_customer_support.fact_customer_contacts` (alias `fcc`), joined to
`dw_customer_support.dim_department` (alias `dd`) on `dd.sk_department = fcc.sk_department`:

```sql
fcc.channel = 'chat'
AND fcc.is_interaction_answered = TRUE
AND dd.department IN (
    '[WH] Alteração de dados bancários [Front]',
    '[AeC] CX Mudança [FRONT] [POS]',
    '[AeC] CX Parceiros Compra e Venda [FRONT]',
    '[AeC] CX Reparos [FRONT] [POS]',
    '[AeC] CX Ongoing [FRONT] [POS]',
    'Consultores imobiliários 5A',
    'CX Mudança [FRONT] [POS]',
    'CX Pagamentos [FRONT] [POS]',
    'CX Parceiros [FRONT] [PRE]',
    'CX Parceiros Compra e Venda [FRONT]',
    'CX Parceiros da Portaria [FRONT] [PRE]',
    'CX Propostas [FRONT] [PRE]',
    'CX Reparos [FRONT] [POS]',
    'CX Rescisão [FRONT] [POS]',
    'CX Visitas [FRONT] [PRE]',
    'OPS COBRANÇA ATIVO [POS]',
    '[AeC] CX Pagamentos [FRONT] [POS]',
    '[AeC] CX Rescisão [FRONT] [POS]',
    '[AeC] CX Visitas [FRONT] [PRE]',
    '[AeC] CX Propostas [FRONT] [PRE]',
    '[AeC] CX Parceiros [FRONT] [PRE]',
    '[AeC] CX Parceiros da Portaria [FRONT] [PRE]'
)
AND (fcc.quinto_andar_phone_number IS NULL OR fcc.quinto_andar_phone_number NOT LIKE '%50285959')
-- Change both bounds to the analysis window you want (half-open interval).
AND fcc.ts_task_created - INTERVAL '3' HOUR >= TIMESTAMP '2026-07-01 00:00:00'
AND fcc.ts_task_created - INTERVAL '3' HOUR < TIMESTAMP '2026-08-01 00:00:00'
```

(`ts_contact` = `fcc.ts_task_created - INTERVAL '3' HOUR` — local-time reporting axis; see Nuances.)

> ⚠️ **MANDATORY FILTER — do not compute this metric without it**
>
> Every query for `% Non Wall-E (POST)` — Golden Query or ad hoc — **must** exclude contacts whose
> `quinto_andar_phone_number` ends in the 8 digits `50285959` (a QuintoAndar-owned support line for
> document/image uploads on *other* tickets, not a real contact). Add this predicate to the same
> `WHERE` clause that builds the universe (`faturaveis_rows` / Canonical Filter above), **before**
> counting numerator or denominator:
>
> ```sql
> AND (fcc.quinto_andar_phone_number IS NULL OR fcc.quinto_andar_phone_number NOT LIKE '%50285959')
> ```
>
> Skipping this filter is not a rounding error: for May–Jul 2026 it roughly **doubles** the
> reported "Non Wall-E" share (e.g. July 2026 goes from the correct 7.73% to a wrong ~19.6%),
> because every contact on this line fails the Wall-E join and gets miscounted as "Non Wall-E" on
> both sides of the ratio. See Scope → Excluded and Nuances for full detail.

**Warning**: Using a narrower or different queue list (e.g. dropping the four non-`[AeC]`-prefixed
entries, or the WH/OPS entries) silently shrinks the universe and distorts the Pre/Post split —
this exact 22-queue list is the one validated against the reference "Contatos Faturáveis" query.
Also: filtering only on `bot = 'wall-e'` sessions without the full `session_key` fallback chain
(Sauron → SSS) under-detects Wall-E origin for older sessions, inflating "Non Wall-E".
Omitting the `ts_created >= 2024-01-01` lookback on `datalake_chatbot.sessions` (or widening
the contact window before 2024) leaves pre-2024 Wall-E sessions unmatched — those contacts get
`is_wall_e = 0` and are mis-counted as Non Wall-E.
Bound the reporting period on `ts_contact`, not raw `ts_task_created` — otherwise contacts near
month boundaries fall in or out of the window relative to the golden query.
Also: forgetting the `quinto_andar_phone_number` exclusion inflates both Pos volume and "Non
Wall-E" share — this line contributed ~11.7k contacts in July 2026 alone (from ~5.5k in May),
almost all landing in `CX Pagamentos [FRONT] [POS]` and `CX Rescisão [FRONT] [POS]`, and is
growing month over month.

### Nuances

**Month bucketing** uses local time, not UTC: `ts_contact = fcc.ts_task_created - INTERVAL '3'
HOUR`. Always group by `DATE_TRUNC('month', ts_contact)`, never by the raw UTC `ts_task_created`.

**First-department derivation** (drives `segmento`):

```sql
first_dept_raw AS (
    SELECT
        COALESCE(NULLIF(CAST(fcc.sk_session AS VARCHAR), '-1'), NULLIF(fcc.sk_support_session, '-1')) AS session_key,
        dd.department AS first_department,
        fcc.ts_task_created
    FROM dw_customer_support.fact_customer_contacts fcc
    LEFT JOIN dw_customer_support.dim_department dd ON dd.sk_department = fcc.sk_department
    WHERE fcc.is_first_interaction = TRUE
      AND fcc.ts_task_created >= TIMESTAMP '2025-01-01 00:00:00'
),
first_department AS (
    SELECT session_key, first_department,
           ROW_NUMBER() OVER (PARTITION BY session_key ORDER BY ts_task_created ASC) AS rn
    FROM first_dept_raw
)
-- join on session_key AND rn = 1
```

This CTE is **not** filtered to `channel = 'chat'` or the 22-queue list — the true first
interaction of a session can be on any channel, in any department (including back-office/triage
queues never billable themselves).

**`segmento` classification** (priority order — first match wins):

| Match on `first_department` | `segmento` |
|---|---|
| Exact match: `CX Mudança/Pagamentos/Reparos/Rescisão/Ongoing [FRONT] [POS]` (+ `[AeC]` variants) | `Pos` |
| Exact match: `CX Parceiros/Propostas/Visitas [FRONT] [PRE]` (+ `[AeC]` variants), `[WH] Closing [FRONT]`, `[WH] Credito [FRONT]`, `ISAIAS AB`, `ISAIAS Inbound`, `IS Outbound - MultiCanais` | `Pre` |
| Contains `[PRE]` | `Pre` |
| Contains `[POS]` | `Pos` |
| Contains `Off Manager`, `dados banc`, `Reparos`, `Vistoria`, `Conta Comigo`, `Porto` | `Pos` |
| Contains `ISAIAS`, starts with `IS ` / `[IS]`, contains `Agents`, `Closing`, `Secretaria`, `fotos`/`Fotos`, `Corretagem`, `Partners`, `Parceiros`, `Consultores imobili...` | `Pre` |
| No match / no `first_department` found | `Outra_origem` (report separately, never silently folded into Pre or Pos) |

**Join key**: `session_key` — the shared identifier between `fact_customer_contacts` and
`datalake_chatbot.sessions`, resolved as Sauron numeric ID first, SSS UUID as fallback (see below).
`Consultores imobiliários 5A` and `CX Parceiros Compra e Venda [FRONT]` (non-`[AeC]`-prefixed
forms — two of the 22 canonical queues themselves) do not contain "Partners" and were the single
biggest source of a wrongly-inflated `Outra_origem` bucket in Jan–Apr 2026 data before the
`%Parceiros%` / `%Consultores imobili%` rules were added. These two queues appear to have been
phased out in favor of the `[AeC]`-prefixed versions from ~May 2026 onward (BPO handoff), so
their volume as `first_department` naturally drops to near-zero from May.

**Wall-E join key** (drives `is_wall_e`) — priority order, **not** ticket-based:

```sql
-- contacts side
COALESCE(NULLIF(CAST(sk_session AS VARCHAR), '-1'), NULLIF(sk_support_session, '-1'))
-- datalake_chatbot.sessions side
COALESCE(NULLIF(CAST(id_sauron_session AS VARCHAR), '-1'), NULLIF(id_sss_session, '-1'))
```

`sk_support_session` / `id_sss_session` (SSS UUID format) only became populated at meaningful
volume from ~April–May 2026 onward; `sk_session` / `id_sauron_session` (legacy Sauron numeric ID)
is the reliable key for older data. Always try Sauron first, SSS as fallback — never SSS-only.

**Wall-E session lookback** (drives `is_wall_e`) — load candidate sessions from
`datalake_chatbot.sessions` with a **fixed** lower bound, independent of the analysis window:

```sql
bot_sessions AS (
    SELECT
        COALESCE(NULLIF(CAST(id_sauron_session AS VARCHAR), '-1'), NULLIF(id_sss_session, '-1')) AS session_key,
        MAX(CASE WHEN bot = 'wall-e' THEN 1 ELSE 0 END) AS is_wall_e
    FROM datalake_chatbot.sessions
    WHERE bot IN ('old bot', 'wall-e')
      AND ts_created >= TIMESTAMP '2024-01-01 00:00:00'
    GROUP BY 1
)
```

Restricting `bot_sessions` to the analysis start date drops Wall-E rows that predate the
analysis window but still own the contact's `session_key`, inflating Non Wall-E. The metric is
validated for reporting from **2024-01-01** onward — do not run it on earlier `ts_contact`
periods.

**Fallback**: A contact whose session has **no** `first_department` match at all (join finds
nothing within the `>= 2025-01-01` lookback, or no valid `session_key`) goes to `Outra_origem`,
not to Pre or Pos. This bucket is usually near-zero (< 0.1% of volume) but spikes for the
**most recent 1–2 weeks of data** due to processing lag on the first-interaction lookup — always
caveat the latest partial period ("UTD") with this limitation rather than trusting Pos/Pre splits
at face value for very recent dates.

**Support/document-upload phone exclusion**: `quinto_andar_phone_number` values ending in the 8
digits `50285959` (observed in production as the full number `551150285959`, i.e. country code
55 + DDD 11 + `50285959`) identify a QuintoAndar-owned WhatsApp line used exclusively so customers
can send documents/images in support of *other, already-open* tickets. Every interaction on this
number is support scaffolding, not an independent contact, so it must be dropped entirely from the
universe (`faturaveis_rows`) — never counted in numerator or denominator. Match on the **last 8
digits only** via `LIKE '%50285959'`, not full equality and not `RIGHT(quinto_andar_phone_number,
8)` (unsupported in this Trino version), because the stored value can carry DDD/country-code
prefix variations. Impact is material and growing: ~59 contacts in April 2026 (line went live),
~5.5k in May, ~10.2k in June, ~11.7k in July — concentrated in `CX Pagamentos [FRONT] [POS]`,
`[AeC]/CX Rescisão [FRONT] [POS]`, `[AeC] CX Pagamentos [FRONT] [POS]`, and `[WH] Alteração de
dados bancários [Front]`, i.e. almost entirely Post-contract. Excluding this line only
meaningfully affects the metric from April 2026 onward. Applying the exclusion to May/June/July
2026: `% Non Wall-E (POST)` = 13.02% (May, 71,380 Pos contacts), 11.80% (June, 73,784), 7.73%
(July, 76,902) — declining month over month as Wall-E POST coverage improves.

## Dos and Don'ts

**Do:**

- Always filter `channel = 'chat' AND is_interaction_answered = TRUE` before anything else.
- Always resolve department names via `dim_department` (`sk_department` join), never assume the
  raw `sk_department` key is human-readable.
- Always classify `segmento` from the session's **first** department (`is_first_interaction`),
  never from the department that made the contact "billable" — those are frequently different
  rows.
- Always use the full session-key fallback chain (Sauron → SSS) on **both** sides of the Wall-E
  join.
- Always load `bot_sessions` with the fixed `ts_created >= TIMESTAMP '2024-01-01 00:00:00'`
  lookback — never narrow it to the analysis start date.
- Always report the `Outra_origem` bucket size alongside the Pos/Pre split — never silently
  redistribute it without flagging the assumption.
- Always exclude `quinto_andar_phone_number` ending in `50285959` (last-8-digit match via
  `LIKE`) from the universe before computing anything — it is document/image-upload scaffolding
  for other tickets, not a real contact.

**Don't:**

- Don't classify Pre/Post by the contact's **current** `sk_department` — this systematically
  over-counts Pos and under-counts Pre (confirmed regression: ~68k/~78k vs. the correct ~64k/~82k
  split for June 2026).
- Don't restrict the "Contatos Faturáveis" universe to a subset smaller than the 22 canonical
  queues (e.g. an 18-queue list dropping WH/OPS/non-AeC-Parceiros entries) — that was a valid cut
  for a *different*, narrower ad-hoc analysis, not for this metric.
- Don't join Wall-E origin via `sk_ticket` / `id_ticket` alone — many escalated Wall-E sessions
  never generate a Zendesk-style ticket post-migration; the session-key join is the primary
  signal, ticket is not used at all in this metric's canonical join.
- Don't treat `is_wall_e` as matching any historical `bot = 'wall-e'` row without the
  `ts_created >= 2024-01-01` lookback, and don't report periods before 2024 — unmatched pre-2024
  Wall-E sessions default to Non Wall-E.
- Don't forget the `Parceiros` / `Consultores imobiliários` keyword rules — omitting them was the
  single largest classification bug found during validation (~85k mis-bucketed contacts in
  Jan–Apr 2026 alone).
- Don't match the `50285959` exclusion with full string equality or `RIGHT()` (unsupported in this
  Trino version) — the stored `quinto_andar_phone_number` can carry DDD/country-code prefixes; use
  `LIKE '%50285959'` and handle `NULL` explicitly.

## Golden Queries

Computes `% Non Wall-E (POST)` by month. The universe CTE (`faturaveis_rows`) reproduces the
"Contatos Faturáveis" pattern documented in the Ticket domain entity, and the
`first_department` CTE reproduces that entity's own first-department pattern; what is exclusive
to this metric is filtering the final aggregation to `segmento = 'Pos'` and computing the
Non-Wall-E share within it.

⚠️ **Before running this query**: confirm the `faturaveis_rows` CTE below still contains the line
`AND (fcc.quinto_andar_phone_number IS NULL OR fcc.quinto_andar_phone_number NOT LIKE
'%50285959')`. If that line is missing or was edited out, the result is wrong — do not report
numbers computed without it.

```sql
WITH departments AS (
    SELECT sk_department, department FROM dw_customer_support.dim_department
),
faturaveis22 AS (
    SELECT * FROM (VALUES
        ('[WH] Alteração de dados bancários [Front]'), ('[AeC] CX Mudança [FRONT] [POS]'),
        ('[AeC] CX Parceiros Compra e Venda [FRONT]'), ('[AeC] CX Reparos [FRONT] [POS]'),
        ('[AeC] CX Ongoing [FRONT] [POS]'), ('Consultores imobiliários 5A'),
        ('CX Mudança [FRONT] [POS]'), ('CX Pagamentos [FRONT] [POS]'),
        ('CX Parceiros [FRONT] [PRE]'), ('CX Parceiros Compra e Venda [FRONT]'),
        ('CX Parceiros da Portaria [FRONT] [PRE]'), ('CX Propostas [FRONT] [PRE]'),
        ('CX Reparos [FRONT] [POS]'), ('CX Rescisão [FRONT] [POS]'),
        ('CX Visitas [FRONT] [PRE]'), ('OPS COBRANÇA ATIVO [POS]'),
        ('[AeC] CX Pagamentos [FRONT] [POS]'), ('[AeC] CX Rescisão [FRONT] [POS]'),
        ('[AeC] CX Visitas [FRONT] [PRE]'), ('[AeC] CX Propostas [FRONT] [PRE]'),
        ('[AeC] CX Parceiros [FRONT] [PRE]'), ('[AeC] CX Parceiros da Portaria [FRONT] [PRE]')
    ) AS t(department)
),
first_dept_raw AS (
    -- Component: first-ever department per session — same pattern as the
    -- first_department CTE in the Ticket entity (is_first_interaction = TRUE,
    -- ranked by ts_task_created).
    -- Fixed lookback from 2025-01-01 — do not narrow to the analysis window.
    SELECT
        COALESCE(NULLIF(CAST(fcc.sk_session AS VARCHAR), '-1'), NULLIF(fcc.sk_support_session, '-1')) AS session_key,
        dd.department AS first_department,
        fcc.ts_task_created
    FROM dw_customer_support.fact_customer_contacts fcc
    LEFT JOIN departments dd ON dd.sk_department = fcc.sk_department
    WHERE fcc.is_first_interaction = TRUE
      AND fcc.ts_task_created >= TIMESTAMP '2025-01-01 00:00:00'
),
first_department AS (
    SELECT session_key, first_department,
           ROW_NUMBER() OVER (PARTITION BY session_key ORDER BY ts_task_created ASC) AS rn
    FROM first_dept_raw
),
faturaveis_rows AS (
    SELECT
        fcc.sk_contact,
        fcc.ts_task_created - INTERVAL '3' HOUR AS ts_contact,
        COALESCE(NULLIF(CAST(fcc.sk_session AS VARCHAR), '-1'), NULLIF(fcc.sk_support_session, '-1')) AS session_key
    FROM dw_customer_support.fact_customer_contacts fcc
    LEFT JOIN departments dd ON dd.sk_department = fcc.sk_department
    WHERE fcc.channel = 'chat'
      AND fcc.is_interaction_answered = TRUE
      AND dd.department IN (SELECT department FROM faturaveis22)
      -- Mandatory: drops the document/image-upload support line — see Nuances.
      AND (fcc.quinto_andar_phone_number IS NULL OR fcc.quinto_andar_phone_number NOT LIKE '%50285959')
      -- Change to the start of the analysis window you want.
      AND fcc.ts_task_created >= TIMESTAMP '2026-07-01 00:00:00'
),
bot_sessions AS (
    -- Fixed lookback from 2024-01-01 — do not narrow to the analysis window.
    SELECT
        COALESCE(NULLIF(CAST(id_sauron_session AS VARCHAR), '-1'), NULLIF(id_sss_session, '-1')) AS session_key,
        MAX(CASE WHEN bot = 'wall-e' THEN 1 ELSE 0 END) AS is_wall_e
    FROM datalake_chatbot.sessions
    WHERE bot IN ('old bot', 'wall-e')
      AND ts_created >= TIMESTAMP '2024-01-01 00:00:00'
    GROUP BY 1
),
classified AS (
    SELECT
        fr.sk_contact,
        fr.ts_contact,
        COALESCE(bs.is_wall_e, 0) AS is_walle,
        CASE
            WHEN fd.first_department IN (
                'CX Mudança [FRONT] [POS]', 'CX Pagamentos [FRONT] [POS]', 'CX Reparos [FRONT] [POS]',
                'CX Rescisão [FRONT] [POS]', 'CX Ongoing [FRONT] [POS]', '[AeC] CX Mudança [FRONT] [POS]',
                '[AeC] CX Reparos [FRONT] [POS]', '[AeC] CX Ongoing [FRONT] [POS]',
                '[AeC] CX Pagamentos [FRONT] [POS]', '[AeC] CX Rescisão [FRONT] [POS]'
            ) THEN 'Pos'
            WHEN fd.first_department IN (
                'CX Parceiros [FRONT] [PRE]', 'CX Propostas [FRONT] [PRE]', 'CX Visitas [FRONT] [PRE]',
                '[AeC] CX Parceiros Compra e Venda [FRONT]', '[AeC] CX Visitas [FRONT] [PRE]',
                '[AeC] CX Propostas [FRONT] [PRE]', '[AeC] CX Parceiros [FRONT] [PRE]',
                '[AeC] CX Parceiros da Portaria [FRONT] [PRE]', '[WH] Closing [FRONT]', '[WH] Credito [FRONT]',
                'ISAIAS AB', 'ISAIAS Inbound', 'IS Outbound - MultiCanais'
            ) THEN 'Pre'
            WHEN fd.first_department LIKE '%[PRE]%' THEN 'Pre'
            WHEN fd.first_department LIKE '%[POS]%' THEN 'Pos'
            WHEN fd.first_department LIKE '%Off Manager%' THEN 'Pos'
            WHEN fd.first_department LIKE '%dados banc%' THEN 'Pos'
            WHEN fd.first_department LIKE '%Reparos%' THEN 'Pos'
            WHEN fd.first_department LIKE '%Vistoria%' THEN 'Pos'
            WHEN fd.first_department LIKE '%Conta Comigo%' THEN 'Pos'
            WHEN fd.first_department LIKE '%Porto%' THEN 'Pos'
            WHEN fd.first_department LIKE '%ISAIAS%' THEN 'Pre'
            WHEN fd.first_department LIKE '[IS]%' OR fd.first_department LIKE 'IS %' THEN 'Pre'
            WHEN fd.first_department LIKE '%Agents%' THEN 'Pre'
            WHEN fd.first_department LIKE '%Closing%' THEN 'Pre'
            WHEN fd.first_department LIKE '%Secretaria%' THEN 'Pre'
            WHEN fd.first_department LIKE '%fotos%' OR fd.first_department LIKE '%Fotos%' THEN 'Pre'
            WHEN fd.first_department LIKE '%Corretagem%' THEN 'Pre'
            WHEN fd.first_department LIKE '%Partners%' THEN 'Pre'
            WHEN fd.first_department LIKE '%Parceiros%' THEN 'Pre'
            WHEN fd.first_department LIKE '%Consultores imobili%' THEN 'Pre'
            ELSE 'Outra_origem'
        END AS segmento
    FROM faturaveis_rows fr
    LEFT JOIN bot_sessions bs ON fr.session_key = bs.session_key
    LEFT JOIN first_department fd ON fr.session_key = fd.session_key AND fd.rn = 1
)
SELECT
    DATE_TRUNC('month', ts_contact) AS mes,
    COUNT(DISTINCT sk_contact) AS total_pos,
    COUNT(DISTINCT CASE WHEN is_walle = 0 THEN sk_contact END) AS non_wall_e_pos,
    ROUND(
        CAST(COUNT(DISTINCT CASE WHEN is_walle = 0 THEN sk_contact END) AS DOUBLE)
        / COUNT(DISTINCT sk_contact), 4
    ) AS pct_non_wall_e_pos
FROM classified
WHERE segmento = 'Pos'
  -- Change both bounds to the analysis window you want (half-open interval).
  AND ts_contact >= TIMESTAMP '2026-07-01 00:00:00'
  AND ts_contact < TIMESTAMP '2026-08-01 00:00:00'
GROUP BY 1
ORDER BY 1
```

