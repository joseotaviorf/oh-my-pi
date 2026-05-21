# Conversation Explorer

## Overview

Conversation Explorer is a **daily sampled subset** of AI chatbot sessions (target **~7.5K sessions per day**) ingested for qualitative review and taxonomy analytics. Each row in `datalake_conversation_explorer_clean.categorisation` carries **Wall-E session categoriser** outputs (categories, resolution labels, friction signals, AI-generated summaries). **`datalake_conversation_explorer_clean.annotations`** holds **human reviewer notes** keyed to the same Langfuse sessions.

**Scope (for now):** Conversation Explorer data exists **only for the Wall-E chatbot** (`datalake_chatbot.sessions.bot = 'wall-e'`). Do not assume Sonia, Matthew, Concierge, or other bots appear in these tables unless product expands coverage.

Tables are partitioned by `year`, `month`, `day` derived from session activity / annotation time — **always constrain partitions** when querying large ranges.

This domain is **not a census** of chatbot traffic. Any metric framed as “share of all bot sessions” or “% of chatbot volume” using `datalake_chatbot.*` totals is **wrong** unless the question explicitly scopes to Conversation Explorer rows only.

## Glossary and Synonyms

- **Conversation Explorer**, **CE**, **conversation explorer bucket** → sampled analytical slice in `datalake_conversation_explorer_clean.*`
- **Domain** → high-level conversation theme in column `category` (business language often says “domain”; SQL column name is `category`)
- **User problem** → finer-grained issue label in column `subcategory` (synonym “sub category”; SQL column name is `subcategory`)
- **Annotation** → free-text note written by a **human reviewer** (`annotations.annotation_text`), not model output — metadata fields `author`, `created_at` describe who wrote it and when
- **Wall-E categoriser**, **session categoriser model** → produces model-assigned labels on the sampled sessions (`categorisation` table); distinct from human annotations

## Tables

| You need... | Use this table |
|-------------|----------------|
| Sampled session taxonomy (domain / user problem, escalation, queues, friction, AI summary) | `datalake_conversation_explorer_clean.categorisation` (`ce_cat`) — grain is **one row per sampled Langfuse session** for that daily extract; merge key `id_langfuse_session`. Filter `year`, `month`, `day` and/or `session_date`. |
| Human reviewer notes on sampled sessions | `datalake_conversation_explorer_clean.annotations` (`ce_ann`) — many annotations possible per session over time; merge key `id_langfuse_session`. Filter `year`, `month`, `day` and/or `created_at`. |

**Critical rules:**

- **Wall-E only (current)** — treat Conversation Explorer as **Wall-E sessions exclusively**; joining to `datalake_chatbot.sessions` should keep `bot = 'wall-e'` when validating cohorts unless future pipelines widen bot coverage.
- **Sampling (~7.5K sessions/day)** — treat every aggregate as **within-sample** unless the user explicitly asks otherwise; state the sample cap when interpreting volumes.
- **Percentage denominators** — compute `%` using **`COUNT(DISTINCT id_langfuse_session)` (or row counts where grain is already session-per-row)** taken **only from Conversation Explorer tables after the same filters as the numerator**. Never divide by totals from `datalake_chatbot.sessions`, Langfuse-wide counts, or “all bot sessions”.
- **Presentation defaults** — answer with **percentages or shares**; avoid raw session counts unless the user requests counts — if they do, **repeat that CE samples ~7.5K sessions/day** and counts are not global traffic.
- **Partitions** — include predicates on `year`, `month`, `day` (and narrow `session_date` / `created_at` when possible) to avoid full scans.
- **`annotations` time ≠ session partition day** — `categorisation` partitions reflect **`session_date`**; `annotations` partitions reflect **`created_at`**. Link on `id_langfuse_session` and compare **`DATE(created_at)`** to **` session_date`** (plus an explicit lag window for “within N days” or cost control). Using the cohort’s **`year/month/day` on both tables silently drops late reviewer work and understates penetration.

## Key Metrics

- Share of sampled sessions by **domain** (`category`) — denominator: distinct `ce_cat.id_langfuse_session` in the filtered categorisation set
- Share of sampled sessions by **user problem** (`subcategory`) — same denominator rule; nest under `category` when both dimensions appear
- Escalation mix among sampled sessions (`is_escalated`) — `%` of filtered CE sessions, not `%` of all chatbot escalations
- Resolution / refinement distribution (`resolution_category`, `resolution_refinement_category`) — CE denominator
- AI resistance / frustration distribution (`ai_resistance`, `frustration`) — CE denominator
- Annotation penetration — e.g. `%` of sampled sessions with ≥1 human annotation in a **defined lag window** (`DATE(created_at) >= session_date`, plus an upper bound if you measure “within N days”); **do not** align `annotations` partitions to categorisation partitions as if both were session day. Denominator from the same CE cohort as Query 3; never compare to global bot sessions

## Relationships with Other Entities

### Chatbot sessions (optional enrichment — N:1 or 1:1 depending on filters)

- Join when you need bot/host/version fields not stored in CE:
  - `datalake_conversation_explorer_clean.categorisation.id_langfuse_session = datalake_chatbot.sessions.id_langfuse_session`
- **Still keep CE-safe denominators**: percentages describing Conversation Explorer taxonomy must divide by CE cohort counts, not by `COUNT(*)` on unfiltered `datalake_chatbot.sessions`.

### Annotations vs categorisation (1:N — zero or many annotations per session)

- `datalake_conversation_explorer_clean.annotations.id_langfuse_session = datalake_conversation_explorer_clean.categorisation.id_langfuse_session`
- Aggregate annotations **per session** before merging to categorisation counts when combining qualitative labels with taxonomy breakdowns.

## Dos and Don'ts

**Do:**

- Express breakdowns as **`pct_of_ce_sessions = 100.0 * ce_metric / ce_denominator`** where both pieces come from the **same filtered Conversation Explorer dataset**
- Use **`COUNT(DISTINCT id_langfuse_session)`** whenever sessions might repeat across joins or date logic
- Clarify that **`annotations`** rows reflect **human judgement**; **`category` / `subcategory`** reflect **model-assigned taxonomy** on the sampled extract
- Call **`category`** “domain” and **`subcategory`** “user problem” when speaking to stakeholders while keeping SQL column names unchanged

**Don't:**

- Compare Conversation Explorer counts or percentages to **total chatbot volume**, **all Langfuse sessions**, or any denominator outside the CE tables for the scoped filter — this invalidates inference
- Present raw daily session totals without reminding readers that CE intentionally caps near **~7.5K sessions/day**
- Assume annotations exist for every sampled session — absence simply means reviewers have not annotated that session in the warehouse extract
- Reuse **`categorisation` `year/month/day`** as the sole filter on **`annotations`** when measuring coverage — **`annotations.day` is keyed to `created_at`**, not `session_date`, and will undercount whenever reviews land on a later calendar day

## Golden Queries

### Query 1 — Domain distribution within Conversation Explorer (percent of sampled sessions)

Describes each **`category` (domain)** as a share of the sampled sessions on a calendar day — denominator is CE only.

```sql
WITH ce_day AS (
    SELECT
        id_langfuse_session,
        category
    FROM
        datalake_conversation_explorer_clean.categorisation
    WHERE
        year = 2026
        AND month = 5
        AND day = 20
),
tot AS (
    SELECT
        COUNT(DISTINCT id_langfuse_session) AS n_sessions
    FROM
        ce_day
)
SELECT
    category AS domain,
    COUNT(DISTINCT ce_day.id_langfuse_session) AS n_sessions_in_domain,
    100.0 * COUNT(DISTINCT ce_day.id_langfuse_session) / tot.n_sessions AS pct_of_ce_sessions
FROM
    ce_day
CROSS JOIN
    tot
GROUP BY
    category,
    tot.n_sessions
ORDER BY
    pct_of_ce_sessions DESC
```

### Query 2 — User problem mix nested under domain

Shows **`subcategory` (user problem)** percentages **within each `category`**, still using Conversation Explorer denominators only.

```sql
WITH ce_day AS (
    SELECT
        id_langfuse_session,
        category,
        subcategory
    FROM
        datalake_conversation_explorer_clean.categorisation
    WHERE
        year = 2026
        AND month = 5
        AND day = 20
),
tot_per_domain AS (
    SELECT
        category,
        COUNT(DISTINCT id_langfuse_session) AS n_sessions_domain
    FROM
        ce_day
    GROUP BY
        category
)
SELECT
    ce_day.category AS domain,
    ce_day.subcategory AS user_problem,
    COUNT(DISTINCT ce_day.id_langfuse_session) AS n_sessions_problem,
    100.0 * COUNT(DISTINCT ce_day.id_langfuse_session) / tot_per_domain.n_sessions_domain AS pct_within_domain
FROM
    ce_day
LEFT JOIN
    tot_per_domain
        ON ce_day.category = tot_per_domain.category
GROUP BY
    ce_day.category,
    ce_day.subcategory,
    tot_per_domain.n_sessions_domain
ORDER BY
    ce_day.category,
    pct_within_domain DESC
```

### Query 3 — Share of sampled sessions that received human annotations

`categorisation` partitions (`year`, `month`, `day`) follow **`session_date`** (when the chat happened). `annotations` partitions follow **`created_at`** (when the reviewer saved the note). Reviewers almost always annotate **after** the session, so **never filter `annotations` with the same `year/month/day` as the categorisation cohort** — you will drop late annotations and **undercount** penetration.

Use the session key plus **`DATE(created_at)` on or after `session_date`**. For cost, add a bounded `created_at` window and matching **annotation** partition range that covers realistic review lag (example below uses 30 days); widen as needed.

```sql
WITH ce_sessions AS (
    SELECT DISTINCT
        id_langfuse_session,
        CAST(session_date AS DATE) AS dt_session
    FROM
        datalake_conversation_explorer_clean.categorisation
    WHERE
        year = 2026
        AND month = 5
        AND day = 20
),
ann_for_cohort AS (
    SELECT DISTINCT
        ann.id_langfuse_session
    FROM
        datalake_conversation_explorer_clean.annotations AS ann
    INNER JOIN
        ce_sessions AS ce
            ON ann.id_langfuse_session = ce.id_langfuse_session
            AND DATE(ann.created_at) >= ce.dt_session
            AND DATE(ann.created_at) <= ce.dt_session + INTERVAL '30' DAY
)
SELECT
    100.0 * COUNT(ann_for_cohort.id_langfuse_session) / COUNT(ce_sessions.id_langfuse_session) AS pct_sessions_with_human_annotation_within_30d
FROM
    ce_sessions
LEFT JOIN
    ann_for_cohort
        ON ce_sessions.id_langfuse_session = ann_for_cohort.id_langfuse_session
```

Rename the metric or drop the upper bound if the question is **ever annotated** (accept larger scans unless you add a generous `created_at` / partition window).
