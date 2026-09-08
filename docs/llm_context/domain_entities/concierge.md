# Concierge

## Ownership

**Data Owner:**
- pedro.nogueira@quintoandar.com.br

**Data Steward:**
- yiyi.ji@quintoandar.com

## Overview

Concierge is an AI Agent that recommends properties, answers property and location questions, and manages visit scheduling, rescheduling, and cancellations across RENT and SALE. It operates in **WhatsApp**, identified to users as **Júlia** (`bot = 'concierge'`).

The lifecycle typically includes:
1. **Contact** — an inbound or outbound WhatsApp interaction is recorded in `datalake_search.concierge_messages`. Outbound contact is Concierge proactively reaching out (daily intent-based triggers, retargeting, classifieds follow-up, TTC follow-up, and follow-up campaigns). Inbound contact is the user starting the conversation (QR code scan, classifieds listing button, marketing click, "Talk to Concierge" button, or a freeform message). **Caveat:** only outbound notifications with a `delivered` or `read` status reach this table — outbound attempts that failed or were never delivered are not recorded.
2. **Property recommendation** — upon user interaction, Concierge can generate property recommendations.
3. **Visit booking** — a visit can be booked directly in the conversation or indirectly from a recommended listing page.
4. **Visit management** — upon request, visits previously booked through any channel can be rescheduled or cancelled.
5. **Demand outcome** — `datalake_search.concierge_demand` connects contacts to bookings, prospect activation, and downstream visit-funnel outcomes.

Not every active user gets an outbound notification. Intent-based triggers are suppressed for users who already received a similar-intent message recently (for example, medium and low intent messages are capped to one per 7 days). Unregistered users who abandon a conversation receive at most one retargeting follow-up the next day.

## Glossary and Synonyms

- **Concierge**, **Júlia** → the WhatsApp search assistant; use the `datalake_search.concierge_messages`, `datalake_search.concierge_demand` and `datalake_search.tof_and_concierge_demand` tables. Not to be confused with the recommendation system inside Mora, which is sometimes also called "concierge" — clarify this distinction whenever the term is ambiguous.
- **inbound flow/ inbound contact/ inbound message** → user-initiated Concierge contact (`concierge_flow = 'inbound'`).
- **outbound flow/ outbound contact/ outbound trigger/ outbound notification** → notification sent by Concierge (`concierge_flow = 'outbound'`).
- **High intent** (outbound) → One of the daily triggers sent to users with a visit booked for D+1; recommends similar listings, prioritizing the same condo or street; sent regardless of prior messages (`concierge_flow_type = 'High intent'`).
- **Medium intent** (outbound) → One of the daily triggers sent to users who showed interest on D-1 without booking (favorited a listing, viewed its schedule page, sent a direct offer on RENT, or viewed the listing 3+ times in the last 3 days); suppressed if a high or medium intent message was already sent in the previous 7 days (`concierge_flow_type = 'Medium intent'`).
- **Qualified / Unqualified low intent** (outbound) → One of the daily triggers sent to users outside the high/medium intent rules. "Qualified" means enough data exists to recommend listings directly; "unqualified" means Concierge first asks for preferences. Each is suppressed if a low intent message was already sent in the previous 7 days (`concierge_flow_type IN ('Qualified low intent', 'Unqualified low intent')`).
- **Retargeting** (outbound) → single next-day follow-up to unregistered users (no 5A account) who started a conversation with Júlia but never registered (`concierge_flow_type = 'Retargeting'`).
- **Classifieds** (outbound) → follow-up to users who requested contact, or clicked to schedule a visit on a QuintoAndar listing on a classifieds portal (ImóvelWeb, Chaves na Mão), but didn't book (`concierge_flow_type IN ('Classifieds', 'Classifieds - Chaves na mão')`).
- **TTC Outbound / TTC QAC Outbound** (outbound) → follow-up recommending the specific listing to users who clicked "Talk to Concierge" (TTC) but never sent a message or booked a visit; the QAC variant applies when the TTC click originated from a classified listing on QuintoAndar (`concierge_flow_type IN ('TTC Outbound', 'TTC QAC Outbound')`).
- **Medium FUP** (outbound) → Follow-up campaign entered on D+1 after a Medium intent trigger on D-0 with no conversion. High intent always supersedes Medium FUP and stops it. Users in the Medium FUP cadence are suppressed as soon as they book one or more visits on any listing through any channel (Concierge, Wall-E, self-service, broker-led) (`concierge_flow_type = 'Medium FUP'`).
- **Placas agent FUP** (outbound) → Concierge follow-up for Placas leads. A Placas lead scans a physical property QR code on a property sign. The system routes the lead to the broker agent who installed the sign. Concierge sends this follow-up when the lead has no TQC (Agent Lead Referral) invite and no visit booking within 7 days after lead distribution. (`concierge_flow_type = 'Placas agent FUP'`).
- **Visit cancellation FUP** (outbound) → Concierge follow-up to recover demand after a cancelled visit. Concierge sends the message on D+1. Not all cancellation reasons are eligible. Product rules define the audience and exclusions. (`concierge_flow_type = 'Visit cancellation FUP'`).
- **Favorites** (outbound) → Concierge trigger that recommends similar listings based on the user's favorites. Classified from `datalake_house_listing_search_clean.concierge_trigger.intent` matching `favorites%` (pipeline key `favorites`), the same way Medium FUP and Visit cancellation FUP are classified. Template suffixes (`_presentation`, `_var1` / `_var2`, `_3cards` / `_4cards` / `_5cards`) are copy and carousel variants of that single flow (`concierge_flow_type = 'Favorites'`).
- **QAC Solicitar contato / QAC contact request** → upon user inquiry about classifieds properties listed on QuintoAndar (QAC) in WhatsApp, if the user shows interest and wants to be contacted by classifieds agents they tap **Solicitar contato**. In data, identify the Copilot session (`id_copilot_session`) via `datalake_jaiminho_clean.user_notifications` where `action = 'ConciergeSendLeadConfirmation_whatsapp_message'` (primary confirmation) or `action = 'ConciergeSendLeadConfirmation_whatsapp_message_fallback'` (when sending the confirmation fails). Join to Copilot via `datalake_copilot_service_clean.message.id_external = user_notifications.id_entity`.
- **Snooze** → user paused Concierge outbound messages via a Privacy Hub consent action; not in `concierge_messages` — matched in `datalake_privacy_hub_clean.transaction` (`purpose_alias = 'SNOOZE_CONCIERGE' AND purpose_status = 'ACTIVE'`).
- **Opt-out** → user withdrew consent to receive Concierge outbound messages; not in `concierge_messages` — matched in `datalake_privacy_hub_clean.transaction` (`purpose_alias = 'TENANT_MESSAGE_AI_INFORMATIVE' AND purpose_status = 'WITHDRAWN'`).
- **Placas** (inbound) → user scans a physical QR code ("Placa") displayed on a property and is directed to Concierge in WhatsApp with a pre-filled message (`concierge_flow_type = 'Placas'`).
- **Chaves na Mão / Imóvel Web** (inbound) → user taps the WhatsApp button on a QuintoAndar listing on these classifieds portals, is directed to Concierge with a pre-filled message (`concierge_flow_type IN ('Imovel web', 'Chaves na mão')`).
- **Click2WPP** (inbound) → user clicks a marketing ad (Facebook, Instagram, YouTube) and is directed to Concierge in WhatsApp with a pre-filled message (`concierge_flow_type = 'Click2WPP'`).
- **TTC / Talk to Concierge** (inbound) → user taps the "Talk to Concierge" button and is directed to Concierge in WhatsApp with a pre-filled message (`concierge_flow_type = 'TTC'`).
- **Freeform** (inbound) → user proactively messages Concierge with no prior trigger (e.g., "hi") (`concierge_flow_type = 'Freeform'`).
- **VB direto** → visit booked or rescheduled through the WhatsApp conversation (`concierge_vb_type = 'direct'`).
- **VB indireto** → visit booked from a listing page recommended by Concierge (`concierge_vb_type = 'indirect'`).
- **ToF activity** → top-of-funnel engagement on QuintoAndar web/app: search, listing page views, and schedule page views (`dt_tof_event IS NOT NULL` in `datalake_search.tof_and_concierge_demand`).
- **Active user** → for logged-in users, distinct `id_user` in `datalake_search.tof_and_concierge_demand` where `dt_tof_event IS NOT NULL`; if `dt_tof_event` is null but `ts_concierge_contact` is not null, the user only interacted with Concierge and had no ToF action. For logged-in and anonymous users combined, use distinct `id_amplitude` in `datalake_search.tof_and_concierge_demand`.
- **Contact prospect** → users contacted by Concierge (inbound or outbound) who had never initiated a RENT/SALE flow, or who had previously churned or initiated a RENT/SALE flow on the day of the Concierge contact (`is_contact_prospect = true`).
- **Concierge prospect** → contact prospects who became a prospect by initiating a RENT/SALE flow through a direct or indirect Concierge-attributed visit booking (`is_concierge_prospect = true`).

## Tables

| You need... | Use this table |
|-------------|----------------|
| Message volume, conversation channel, flow type, and human/audio replies | `datalake_search.concierge_messages` — one or more contact records per conversation; use `id_phone_session` as the phone-and-session identifier. |
| Full Concierge journey from contact through booking, prospect activation, visit completion, offer, and contract signing | `datalake_search.concierge_demand` — primary analysis table; includes direct and indirect booking attribution. |
| Concierge users compared with top-of-funnel search and listing-page activity | `datalake_search.tof_and_concierge_demand` — combines Concierge demand with same-day top-of-funnel activity. |
| QAC contact requests ("Solicitar contato") and QAC request rate | `datalake_jaiminho_clean.user_notifications` joined to `datalake_copilot_service_clean.message` for the numerator; denominator is distinct `id_copilot_session` in `datalake_search.concierge_messages` (Query 7). |

**Critical rules:**
- Filter `year`, `month`, and `day` on all `datalake_search.concierge_*` tables.
- Count unique Concierge users with `user_phone`, not `id_user`, because users can be unregistered or have different Copilot and visit identifiers.
- Count conversations with `id_phone_session`; rows in `concierge_demand` can represent different visit events for the same conversation.
- `concierge_messages` has no native `business_context`. To segment by business context, use `datalake_search.tof_and_concierge_demand` and explain how context is inferred.
- On `datalake_search.tof_and_concierge_demand`, always use `dt_tof_or_concierge` as the date reference. Other date filters can bias the cohort — for example, filtering on `ts_concierge_contact` returns only contacted users and excludes active users who were not contacted.
- `user_phone` is personal data. Do not select or expose it unless it is essential and permitted.

## Key Metrics

- **Volume of Delivered Outbound Notifications:** distinct `id_notification` where `concierge_flow = 'outbound'` and `concierge_flow_type <> 'Undefined'` in `datalake_search.concierge_messages`.
- **Volume of Inbound Messages:** distinct `id_message` where `concierge_flow = 'inbound'` and `concierge_flow_type <> 'Automatic reply to previous message'` in `datalake_search.concierge_messages`. `'Automatic reply to previous message'` is not a genuine flow type — it tags quick-reply button clicks (e.g., "Sim, ver imóveis") used internally to catch the visits triggered from these replies, so it's excluded from inbound message volume.
- **Volume of Concierge conversations:** distinct `id_phone_session` in `datalake_search.concierge_messages`.
- **Human-reply rate of outbound notifications:** share of delivered outbound notifications where `has_human_reply = true` in `datalake_search.concierge_messages`.
- **Human replies with audio:** share of conversations where the user replied with audio (`has_audio = true` in `datalake_search.concierge_messages`).
- **Snooze / Opt-out rate of delivered outbound notifications:** share of delivered outbound notifications matched to a Privacy Hub consent transaction in `datalake_privacy_hub_clean.transaction`, split by `purpose_alias`/`purpose_status` and by intent (`concierge_flow_type`) (see Glossary and Relationships below for the match logic and its caveats).
- **Volume of visit booking, visit completion, offer submission, offer acceptance, and contract signing:** distinct `id_visit` with the corresponding `is_*` flag in `datalake_search.concierge_demand`.
- **Volume of direct/indirect visits from concierge:** distinct `id_visit` by `concierge_vb_type` in `datalake_search.concierge_demand`.
- **Volume of contacted users:** distinct `user_phone` in `datalake_search.concierge_messages`.
- **Volume of contact prospects:** distinct `user_phone` where `is_contact_prospect = true` in `datalake_search.concierge_demand`.
- **Volume of users who booked a visit with concierge:** distinct `user_phone` where `is_visit_booked = true` in `datalake_search.concierge_demand`.
- **Volume of concierge prospect:** distinct `user_phone` where `is_concierge_prospect = true` in `datalake_search.concierge_demand`.
- **QAC request rate:** share of Concierge Copilot sessions (`id_copilot_session` in `datalake_search.concierge_messages`) where the user tapped **Solicitar contato** during a QAC classifieds inquiry; numerator from Query 7 (`user_notifications.action IN ('ConciergeSendLeadConfirmation_whatsapp_message', 'ConciergeSendLeadConfirmation_whatsapp_message_fallback')`), denominator distinct `id_copilot_session` in `datalake_search.concierge_messages`.

## Relationships with Other Entities

### Visits (one Concierge contact to zero or more visits)

- Join Concierge journey data to the Visit entity with `datalake_search.concierge_demand.id_visit = dw_visit.dim_visit.id_visit`.
- Use `id_visit` as the visit-level identifier when measuring direct or indirect bookings; one contact can lead to more than one visit event.

### Tenant or Buyer Prospects (zero or one attributed prospect event per journey row)

- `datalake_search.concierge_demand` derives prospect attribution from `dw_growth.fact_demand_prospect_events`, matching on `id_user` and `id_visit`.

### Chatbot sessions (one Concierge conversation to one Copilot session)

- `datalake_search.concierge_messages.id_copilot_session` identifies the underlying Copilot conversation. 
- `datalake_search.concierge_messages.id_langfuse_session` identifies the underlying chatbot conversation. For general chatbot-host analysis, see [`chatbot_sessions.md`](chatbot_sessions.md).

Every contact always creates a Copilot session (`id_copilot_session`), but a langfuse session (`id_langfuse_session`) is only created when an AI-generated answer is involved. Outbound notifications are templates, not AI-generated, so they only get a langfuse session if the user replies and that reply needs an AI-generated answer.

QAC **Solicitar contato** requests are not in `concierge_messages`; identify them via the Jaiminho actions in Query 7 and measure **QAC request rate** against all `id_copilot_session` in `concierge_messages`.

### Privacy Hub consent transactions (zero or one snooze/opt-out event per delivered outbound notification)

- Snooze and opt-out signals are not in `concierge_messages`; they live in `datalake_privacy_hub_clean.transaction`. Match a notification with `datalake_search.concierge_messages.id_langfuse_session = json_extract_scalar(t.custom_attributes, '$.sessionId')` when the session id is available, or with `datalake_search.concierge_messages.user_phone = json_extract_scalar(t.custom_attributes, '$.whatsappPhone')` and `t.ts_created_at > concierge_messages.ts_concierge_contact` otherwise (take the most recent prior notification, since a phone can match several).
- **Caveat:** Privacy Hub stopped propagating `sessionId` in June 2026 and only started propagating `whatsappPhone` on 01 July 2026 — a transaction may only be matchable through one of the two keys depending on its date.

## Dos and Don'ts

**Do:**
- Use `datalake_search.concierge_demand` for conversion analysis because it combines contact, booking, prospect, and visit outcome fields.
- Segment direct and indirect bookings with `concierge_vb_type`; indirect bookings are self-service listing-page bookings, not WhatsApp booking requests.
- Use `ts_first_concierge_contact` for a user's first Concierge exposure and `ts_concierge_contact` for the specific contact record.

**Don't:**
- Do not treat `visit_request_channel = 'WHATSAPP_CONCIERGE'` as the definition of every Concierge-attributed visit: indirect bookings normally have a self-service channel.
- Do not infer a direct booking from a missing chat row; `concierge_flow_type = 'Unknown'` can occur when the booking user differs from the contacted user.
- Do not use `is_contact_prospect` and `is_concierge_prospect` interchangeably; the latter requires Concierge-attributed booking evidence.

## Golden Queries

### Query 1 — Weekly Volume of Delivered Outbound Notifications

This pattern measures weekly distinct delivered outbound notifications by flow type.

```sql
SELECT
    DATE_TRUNC('week', CAST(ts_concierge_contact AS TIMESTAMP)) AS wk_contact,
    concierge_flow_type,
    COUNT(DISTINCT id_notification) AS n_delivered_notifications
FROM datalake_search.concierge_messages
WHERE year = 2026
    AND month BETWEEN 5 AND 7
    AND concierge_flow = 'outbound'
    AND concierge_flow_type <> 'Undefined'
GROUP BY 1, 2
ORDER BY 1 DESC, 2;
```

### Query 2 — Weekly Response Rate of Delivered Outbound Notifications

This pattern measures the weekly share of delivered outbound notifications that received a human reply, by flow type.

```sql
SELECT
    DATE_TRUNC('week', CAST(ts_concierge_contact AS TIMESTAMP)) AS wk_contact,
    concierge_flow_type,
    COUNT(DISTINCT id_notification) AS n_delivered_notifications,
    COUNT(DISTINCT CASE WHEN has_human_reply THEN id_notification END) AS n_notifications_with_human_reply,
    COUNT(DISTINCT CASE WHEN has_human_reply THEN id_notification END) * 100.0
        / NULLIF(COUNT(DISTINCT id_notification), 0) AS human_reply_rate
FROM datalake_search.concierge_messages
WHERE year = 2026
    AND month BETWEEN 5 AND 7
    AND concierge_flow = 'outbound'
    AND concierge_flow_type <> 'Undefined'
GROUP BY 1, 2
ORDER BY 1 DESC, 2;
```

### Query 3 — Weekly Volume of Inbound Messages

This pattern measures weekly distinct inbound messages by flow type, excluding the automatic-reply artifact.

```sql
SELECT
    DATE_TRUNC('week', CAST(ts_concierge_contact AS TIMESTAMP)) AS wk_contact,
    concierge_flow_type,
    COUNT(DISTINCT id_message) AS n_inbound_messages
FROM datalake_search.concierge_messages
WHERE year = 2026
    AND month BETWEEN 5 AND 7
    AND concierge_flow = 'inbound'
    AND concierge_flow_type <> 'Automatic reply to previous message'
GROUP BY 1, 2
ORDER BY 1 DESC, 2;
```

### Query 4 — Weekly Concierge-attributed Booking Funnel

This pattern measures weekly distinct booked visits and downstream outcomes by business context and direct versus indirect Concierge attribution.

```sql
SELECT
    DATE_TRUNC('week', CAST(ts_visit_created AS TIMESTAMP)) AS wk_visit_created,
    business_context,
    concierge_vb_type,
    COUNT(DISTINCT CASE WHEN is_visit_booked THEN id_visit END) AS n_visits_booked,
    COUNT(DISTINCT CASE WHEN is_visit_completed THEN id_visit END) AS n_visits_completed,
    COUNT(DISTINCT CASE WHEN is_offer_submitted THEN id_visit END) AS n_offers_submitted,
    COUNT(DISTINCT CASE WHEN is_offer_accepted THEN id_visit END) AS n_offers_accepted,
    COUNT(DISTINCT CASE WHEN is_contract_signed THEN id_visit END) AS n_contracts_signed
FROM datalake_search.concierge_demand
WHERE year = 2026
    AND month BETWEEN 5 AND 7
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 2, 3;
```

### Query 5 — Weekly Concierge Prospect Funnel

This pattern measures the weekly contact-to-prospect funnel, from active users through Concierge prospects. Uses `dt_tof_or_concierge` as the date reference, per the Critical rules above. `n_contacted_users` counts distinct `user_phone` (non-null only — Concierge contact rows).

```sql
SELECT
    DATE_TRUNC('week', dt_tof_or_concierge) AS wk_tof_or_concierge,
    business_context,
    COUNT(DISTINCT id_amplitude) AS n_active_users,
    COUNT(DISTINCT user_phone) AS n_contacted_users,
    COUNT(DISTINCT CASE WHEN is_contact_prospect THEN user_phone END) AS n_contact_prospects,
    COUNT(DISTINCT CASE WHEN is_visit_booked THEN user_phone END) AS n_contacted_users_with_vb,
    COUNT(DISTINCT CASE WHEN is_concierge_prospect THEN user_phone END) AS n_concierge_prospects
FROM datalake_search.tof_and_concierge_demand
WHERE year = 2026
    AND month BETWEEN 5 AND 7
GROUP BY 1, 2
ORDER BY 1 DESC, 2;
```

### Query 6 — Weekly Snooze / Opt-out Rate per Intent

This pattern measures the weekly share of delivered outbound notifications that were followed by a snooze or opt-out, broken down by intent (`concierge_flow_type`). Each notification is matched to a Privacy Hub consent transaction by session id or by phone (most recent prior notification wins).

The `session_match` and `phone_match` CTEs use different transaction date windows because Privacy Hub changed which identifier is available over time (see Privacy Hub consent transactions above). When analyzing only from July 2026 onward, use `phone_match` alone and drop `session_match`. When extending the analysis period, update both the notification filter and the matching CTE date bounds — not just `base_notifications`. June 2026 may have incomplete matches because `sessionId` stopped propagating before `whatsappPhone` became available.

```sql
-- Privacy Hub match eras:
--   session_match: notifications before Jul 2026 (match on custom_attributes.sessionId)
--   phone_match: notifications from Jul 2026 onward (match on custom_attributes.whatsappPhone)
-- For post-Jul 2026 analysis only, remove session_match and keep phone_match.
WITH base_notifications AS (
    SELECT
        id_notification,
        id_langfuse_session,
        user_phone,
        ts_concierge_contact,
        concierge_flow_type
    FROM datalake_search.concierge_messages
    WHERE concierge_flow = 'outbound'
        AND concierge_flow_type <> 'Undefined'
        AND year = 2026
        AND month BETWEEN 5 AND 7
),

phone_match AS (
    -- Privacy Hub started propagating whatsappPhone on 01 July 2026;
    -- match the pause/opt-out to the most recent prior outbound notification
    SELECT
        t.id AS transaction_id,
        n.id_notification,
        n.ts_concierge_contact,
        n.concierge_flow_type,
        t.purpose_alias,
        t.purpose_status,
        ROW_NUMBER() OVER (PARTITION BY t.id ORDER BY n.ts_concierge_contact DESC) AS rn
    FROM base_notifications n
    JOIN datalake_privacy_hub_clean.transaction t
        ON json_extract_scalar(t.custom_attributes, '$.whatsappPhone') = n.user_phone
        AND t.year = 2026
        AND t.month = 7
        AND t.ts_created_at >= DATE '2026-07-01'
        AND t.ts_created_at < DATE '2026-08-01'
        AND t.ts_created_at > n.ts_concierge_contact
        AND (
            (t.purpose_alias = 'SNOOZE_CONCIERGE' AND t.purpose_status = 'ACTIVE')
            OR (t.purpose_alias = 'TENANT_MESSAGE_AI_INFORMATIVE' AND t.purpose_status = 'WITHDRAWN')
        )
        AND json_extract_scalar(t.custom_attributes, '$.whatsappPhone') IS NOT NULL
),

session_match AS (
    -- Privacy Hub ceased propagating sessionId from June 2026
    SELECT
        t.id AS transaction_id,
        n.id_notification AS user_notification_id,
        n.ts_concierge_contact AS ts_sent,
        n.concierge_flow_type,
        t.purpose_alias,
        t.purpose_status
    FROM base_notifications n
    JOIN datalake_privacy_hub_clean.transaction t
        ON json_extract_scalar(t.custom_attributes, '$.sessionId') = n.id_langfuse_session
        AND t.year = 2026
        AND t.month BETWEEN 5 AND 6
        AND t.ts_created_at >= DATE '2026-05-01'
        AND t.ts_created_at < DATE '2026-07-01'
        AND (
            (t.purpose_alias = 'SNOOZE_CONCIERGE' AND t.purpose_status = 'ACTIVE')
            OR (t.purpose_alias = 'TENANT_MESSAGE_AI_INFORMATIVE' AND t.purpose_status = 'WITHDRAWN')
        )
        AND json_extract_scalar(t.custom_attributes, '$.sessionId') IS NOT NULL
),

matched AS (
    -- delivered outbound notifications that were followed by a snooze/opt-out
    SELECT
        transaction_id,
        id_notification,
        ts_concierge_contact,
        concierge_flow_type,
        purpose_alias,
        purpose_status
    FROM phone_match
    WHERE rn = 1

    UNION ALL

    SELECT
        transaction_id,
        user_notification_id,
        ts_sent,
        concierge_flow_type,
        purpose_alias,
        purpose_status
    FROM session_match
),

unmatched AS (
    -- delivered outbound notifications with no snooze/opt-out
    SELECT
        CAST(NULL AS BIGINT) AS transaction_id,
        n.id_notification,
        n.ts_concierge_contact,
        n.concierge_flow_type,
        CAST(NULL AS VARCHAR) AS purpose_alias,
        CAST(NULL AS VARCHAR) AS purpose_status
    FROM base_notifications n
    WHERE NOT EXISTS (
        SELECT 1
        FROM matched m
        WHERE m.id_notification = n.id_notification
    )
),

final AS (
    SELECT DISTINCT
        transaction_id,
        id_notification,
        concierge_flow_type,
        CASE
            WHEN purpose_alias = 'SNOOZE_CONCIERGE' THEN 'Snooze'
            WHEN purpose_alias = 'TENANT_MESSAGE_AI_INFORMATIVE' THEN 'Opt-out'
        END AS pause_type,
        DATE_TRUNC('week', CAST(ts_concierge_contact AS TIMESTAMP)) AS wk_notification_sent
    FROM (
        SELECT * FROM matched
        UNION ALL
        SELECT * FROM unmatched
    )
)

SELECT
    wk_notification_sent,
    concierge_flow_type,
    COUNT(DISTINCT CASE WHEN pause_type = 'Snooze' THEN transaction_id END) * 100.0
        / NULLIF(COUNT(DISTINCT id_notification), 0) AS pct_snoozes,
    COUNT(DISTINCT CASE WHEN pause_type = 'Opt-out' THEN transaction_id END) * 100.0
        / NULLIF(COUNT(DISTINCT id_notification), 0) AS pct_optouts
FROM final
GROUP BY 1, 2
ORDER BY 1 DESC, 2;
```

### Query 7 — Weekly QAC Request Rate

This pattern measures the weekly share of Concierge sessions where the user tapped **Solicitar contato** during a WhatsApp inquiry about QuintoAndar Classifieds (QAC) properties. The denominator is all distinct `id_copilot_session` in `datalake_search.concierge_messages`; the numerator is sessions with a matching Jaiminho confirmation (`ConciergeSendLeadConfirmation_whatsapp_message` or `ConciergeSendLeadConfirmation_whatsapp_message_fallback`).

```sql
WITH concierge_sessions AS (
    SELECT DISTINCT
        id_copilot_session,
        DATE_TRUNC('week', CAST(ts_concierge_contact AS TIMESTAMP)) AS wk_contact
    FROM datalake_search.concierge_messages
    WHERE year = 2026
        AND month BETWEEN 5 AND 7
        AND id_copilot_session IS NOT NULL
),

qac_request_sessions AS (
    SELECT DISTINCT
        m.id_session AS id_copilot_session
    FROM datalake_jaiminho_clean.user_notifications un
    INNER JOIN datalake_copilot_service_clean.message m
        ON m.id_external = un.id_entity
    WHERE un.channel = 'whatsapp'
        AND un.action IN (
            'ConciergeSendLeadConfirmation_whatsapp_message',
            'ConciergeSendLeadConfirmation_whatsapp_message_fallback'
        )
        AND un.year = 2026
        AND un.month BETWEEN 5 AND 7
),

session_flags AS (
    SELECT
        cs.wk_contact,
        cs.id_copilot_session,
        CASE
            WHEN q.id_copilot_session IS NOT NULL THEN 1
            ELSE 0
        END AS has_qac_request
    FROM concierge_sessions cs
    LEFT JOIN qac_request_sessions q
        ON cs.id_copilot_session = q.id_copilot_session
)

SELECT
    wk_contact,
    COUNT(DISTINCT id_copilot_session) AS n_concierge_sessions,
    COUNT(DISTINCT CASE WHEN has_qac_request = 1 THEN id_copilot_session END) AS n_qac_request_sessions,
    ROUND(
        100.0 * COUNT(DISTINCT CASE WHEN has_qac_request = 1 THEN id_copilot_session END)
        / NULLIF(COUNT(DISTINCT id_copilot_session), 0),
        2
    ) AS qac_request_rate_pct
FROM session_flags
GROUP BY 1
ORDER BY 1 DESC;
```

## DataHub catalog

> Added automatically by CI after merge.
