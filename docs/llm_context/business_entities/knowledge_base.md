# Knowledge Base

## Overview

The Knowledge Base is the catalog of help articles that QuintoAndar's customer support **Operations** teams use to answer user requests — how to handle a refund, what the Proteção QuintoAndar covers, how a CPF gets unblocked for credit analysis, etc. The data in `datalake_knowledge_base_clean` is a dump of the `knowledge_base` transactional Postgres database: one row per article (`bot_content`), plus its editorial taxonomy (`meta_information`), in-app/web deep links (`deep_link`), and the many-to-many tables that wire them together.

> **Big caveat — this is Operations documentation, not necessarily a business source of truth.** The articles describe *how customer support should handle situations, plus some guidelines and information on how the business work* to a given situation. There is a lot of genuine business knowledge embedded in the text (policies, fees, deadlines, eligibility rules), but it is written for the support/operations context, can lag behind the actual product, and is **not** the authoritative source for any policy, metric, or contractual rule. Treat it as "what Operations tells users" — useful for discovery and context, never as the system of record. For real metrics or policy values, go to the owning domain's DW/enrich tables.

Each article (`bot_content`) carries the answer body in two channels — `web_content` and `app_content` — stored as **JSON rich-text strings**, plus a list of example `questions` it is meant to answer. Articles are grouped under a `meta_information` theme (product + journey), and may link out to one or more `deep_link` URLs.

## Glossary and Synonyms

- **Knowledge Base**, **KB**, **base de conhecimento**, **central de ajuda**, **artigos de atendimento** → the article catalog in `datalake_knowledge_base_clean`
- **Bot content**, **artigo**, **conteúdo** → a single help article (`bot_content`) — the answer body shown on web/app and used by the support bot
- **Meta information**, **tema**, **assunto** → the editorial grouping of articles (`meta_information.theme`), scoped by `product` and `journey`
- **Deep link** → an actionable URL surfaced alongside an article (`deep_link.link`, `deep_link.label`)
- **Product** (`meta_information.product`) → business line the article belongs to: `FOR_RENT`, `FOR_SALE`, `QUINTO_CRED`, `REDE`, `INSTITUCIONAL`
- **Journey** (`meta_information.journey`) → lifecycle stage the article applies to: `PRE_CONTRACT`, `ONBOARDING`, `ONGOING`, `POS_CONTRACT`, `OFFBOARDING`, `ALL`
- **Customer type** (`bot_content.customer_type`) → persona(s) the article targets, JSON array of: `TENANT` (inquilino), `LANDLORD` (proprietário), `BUYER` (comprador), `SELLER` (vendedor), `BROKER`/`CONSULTANT`/`REAL_ESTATE_PARTNER` (corretor/parceiro), `PP_MULTI`, `SURVEYOR`, `PHOTOGRAPHER`. Empty (`[]`) is common.
- **Department** (`bot_content.department_front` / `department_back`) → the support queue that owns the article (e.g. `CX Visitas [FRONT] [PRE]`, `CX Pagamentos [FRONT] [POS]`). Same vocabulary as the support routing domain (see `department.md`).
- **Status** → `ACTIVE` / `INACTIVE`. Only `ACTIVE` articles are live for support; `INACTIVE` are retired drafts. Applies to both `bot_content` and `meta_information`.

## Tables

All tables live in `datalake_knowledge_base_clean` (clean layer, one row per primary key — the CDC dump is already deduplicated to the current state, no hard deletes).

| You need... | Use this table |
|-------------|----------------|
| The article itself (title, answer body, target persona, status, owning department) | `datalake_knowledge_base_clean.bot_content` (`bc`) — one row per article, PK `id`. Body lives in `web_content` / `app_content` (JSON rich-text strings); `questions` is a newline-separated list of example questions; `country`, `customer_type`, `bot_tags` are JSON arrays stored as `varchar`. |
| The editorial taxonomy / grouping of articles (theme, product, journey) | `datalake_knowledge_base_clean.meta_information` (`mi`) — one row per theme, PK `id`. |
| Which articles belong to which theme, and in what order | `datalake_knowledge_base_clean.meta_information_bot_content` (`mibc`) — bridge, PK (`id_meta_information`, `id_bot_content`), with `bot_content_order`. |
| Actionable links (URLs) surfaced with articles | `datalake_knowledge_base_clean.deep_link` (`dl`) — one row per link, PK `id`. |
| Which deep links belong to which article, and in what order | `datalake_knowledge_base_clean.bot_content_deep_link` (`bcdl`) — bridge, PK (`id_bot_content`, `id_deep_link`), with `deep_link_order`. |

**Critical rules:**
- **Always filter `status = 'ACTIVE'`** on `bot_content` (and on `meta_information` when joining through it). `INACTIVE` rows are retired/drafts.
- **Exclude test/junk articles.** There is editorial test data in production — e.g. titles/themes containing `DO NOT USE`, `teste`, `B version`. Filter them out when reporting (`title NOT LIKE '%DO NOT USE%'`, etc.).
- **`web_content` / `app_content` are JSON strings, not plain text.** To read the body, extract the `"value": "..."` nodes — e.g. `ARRAY_JOIN(REGEXP_EXTRACT_ALL(web_content, '"value": "([^"]*)"', 1), ' ')`. Do not display the raw JSON to a user.
- **`customer_type`, `country`, `bot_tags` are JSON arrays stored as `varchar`.** Use `JSON_EXTRACT` / `JSON_ARRAY_CONTAINS` (e.g. `JSON_ARRAY_CONTAINS(customer_type, 'TENANT')`) rather than string matching.
- **No partition columns.** These are small tables (~1.9K articles); a full scan is cheap. Filter on `ts_updated` only when you need recency.
- **Two identifiers, two purposes:** `bot_content.id` (numeric PK) joins the **internal bridge tables** (`meta_information_bot_content`, `bot_content_deep_link`); `bot_content.id_content` (source content UUID) is what **external consumers** reference — notably the Wall-E bot retrieval (`search_documents_v1` → `$.articles[].content_id`). Don't mix them up.

## Key Metrics

This is a content catalog, not a fact table — there are no business KPIs here, only **content-inventory** measures:

- Active article count (`COUNT(*)` on `bot_content WHERE status = 'ACTIVE'`)
- Coverage by owning department (`bot_content.department_front`)
- Freshness / staleness (`ts_updated` distribution — how recently articles were edited)
- Article retrieval volume by the Wall-E bot (count / distinct sessions per article via the Langfuse `search_documents_v1` observation — see Relationships)

## Relationships with Other Entities

### Meta Information ↔ Bot Content (N:N via bridge)

- `meta_information.id = meta_information_bot_content.id_meta_information`
- `meta_information_bot_content.id_bot_content = bot_content.id`
- Order within a theme: `meta_information_bot_content.bot_content_order`

### Chatbot retrieval (article usage by the support bots) — the main consumer

This is how KB articles connect to actual usage and outcomes. Support bots run a RAG retrieval tool over the knowledge base, logged in Langfuse as the observation **`name = 'search_documents_v1'`**. That observation's `output` JSON carries the articles retrieved for the turn, under `$.articles[].content_id`.

- **Join key:** `content_id` from the retrieval output = `bot_content.id_content` (the source content UUID — **not** the numeric PK `id`). Validated: 100% of retrieved `content_id`s match an `id_content` in `bot_content`.
- **Path to KB:** `observations.id_trace = traces.id_trace`, then explode `JSON_EXTRACT(output, '$.articles')`, then `content_id = bot_content.id_content`.
- **Path to session / outcome:** `traces.id_session = sessions.id_langfuse_session`; session resolution comes from `datalake_chatbot.evals` via `ELEMENT_AT(evals, 'RetentionEvaluator').value` / `ELEMENT_AT(evals, 'ResolutionEvaluator').value`. Scope to a specific bot with `sessions.bot` (the support bot Wall-E is the current main consumer).
- **Grain:** one row per (trace, retrieved article); a single bot turn can retrieve several articles, and a session has many traces. De-duplicate to `DISTINCT (id_session, content_id)` before counting sessions.
- **Caveats:** retrieval ≠ the article fully resolved the user — it only means the bot surfaced it. Resolution evals are **sampled**, so `resolution` is frequently NULL; never treat retrieval counts as resolution rates. For full session/eval semantics see `chatbot_sessions.md` and `evals.md`.

## Dos and Don'ts

**Do:**
- Always filter `bot_content.status = 'ACTIVE'` (and `meta_information.status = 'ACTIVE'` when joining) to look at live content.
- Exclude test articles via `title`/`theme` `NOT LIKE` filters (`DO NOT USE`, `teste`, `B version`).
- Extract readable text from `web_content`/`app_content` with `REGEXP_EXTRACT_ALL(..., '"value": "([^"]*)"', 1)` before showing it.
- Use `JSON_ARRAY_CONTAINS(customer_type, 'TENANT')` to filter by persona, and the same on `country` / `bot_tags`.
- Use `meta_information.product` and `meta_information.journey` to scope by business line and lifecycle stage.
- Treat this as a discovery/context source for "what does Operations tell users about X"
- For bot-usage analysis, join `bot_content.id_content` to the `search_documents_v1` observation output (`$.articles[].content_id`), and reach sessions/outcomes through `traces.id_session` → `sessions`/`evals` (`bot = 'wall-e'`).

**Don't:**
- Don't treat article text as authoritative for any metric — it is Operations-facing guidance that can be stale or simplified.
- Don't read `web_content`/`app_content` as plain text — they are JSON rich-text strings.
- Don't string-match `customer_type`/`country`/`bot_tags` as if they were scalars — they are JSON arrays.
- Don't forget the `ACTIVE` filter — over half of `bot_content` rows are `INACTIVE`.
- Don't join the bridge tables on `id_content` — use the numeric PK `id`. Conversely, don't join bot retrieval on `id` — it uses `id_content`.
- Don't read article retrieval (`search_documents_v1`) as a resolution rate — retrieval only means the bot surfaced the article, and resolution evals are sampled (often NULL).

## Golden Queries

### Query 1 — Most retrieved KB articles by the support bot

How often the Wall-E bot surfaces each active article, with distinct-session reach. This is the "which articles actually get used" view behind the article-usage dashboard.

```sql
WITH retrievals AS (
    SELECT
        t.id_session,
        t.id_trace,
        art.content_id
    FROM
        datalake_langfuse_clean.observations AS o
    INNER JOIN
        datalake_langfuse_clean.traces AS t
            ON t.id_trace = o.id_trace
    CROSS JOIN UNNEST(
        CAST(JSON_EXTRACT(o.output, '$.articles') AS ARRAY(ROW(content_id VARCHAR)))
    ) AS art(content_id)
    WHERE
        o.name = 'search_documents_v1'
        AND o.ts_started >= TIMESTAMP '{start_date}'
        AND t.ts_created >= TIMESTAMP '{start_date}'
)
SELECT
    bc.id_content,
    bc.title,
    bc.department_front,
    COUNT(*) AS total_retrievals,
    COUNT(DISTINCT r.id_session) AS distinct_sessions
FROM
    retrievals AS r
INNER JOIN
    datalake_knowledge_base_clean.bot_content AS bc
        ON r.content_id = bc.id_content
        AND bc.status = 'ACTIVE'
GROUP BY
    bc.id_content,
    bc.title,
    bc.department_front
ORDER BY
    total_retrievals DESC
```

### Query 2 — Article catalog with theme, product and journey

Live articles with their editorial taxonomy and a readable preview of the web body — for browsing/searching the catalog itself (no bot usage).

```sql
SELECT
    bc.id,
    bc.id_content,
    bc.title,
    mi.theme,
    mi.product,
    mi.journey,
    bc.department_front,
    SUBSTR(
        ARRAY_JOIN(REGEXP_EXTRACT_ALL(bc.web_content, '"value": "([^"]*)"', 1), ' '),
        1,
        500
    ) AS web_text_preview
FROM
    datalake_knowledge_base_clean.bot_content AS bc
JOIN
    datalake_knowledge_base_clean.meta_information_bot_content AS mibc
        ON bc.id = mibc.id_bot_content
JOIN
    datalake_knowledge_base_clean.meta_information AS mi
        ON mibc.id_meta_information = mi.id
WHERE
    bc.status = 'ACTIVE'
    AND mi.status = 'ACTIVE'
    AND bc.title NOT LIKE '%DO NOT USE%'
    AND mi.theme NOT LIKE '%teste%'
ORDER BY
    mi.product,
    mi.journey,
    mi.theme,
    mibc.bot_content_order
```
