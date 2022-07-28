WITH app_205027_referral_form_events AS (
    SELECT
        CAST(REGEXP_EXTRACT(id_lead, '(^\\d+)') AS BIGINT) AS id_lead,
        NULL AS id_firestore,
        NULL AS formfield_lead_uuid,
        1 AS rule_num,
        'referral' AS rule,
        ts_event,
        utm_campaign,
        utm_medium,
        utm_source,
        utm_content,
        utm_term,
        app_type AS platform,
        referring_domain,
        region,
        city,
        uuid
    FROM
        datalake_amplitude_clean.205027_referral_form_accepted_events
    WHERE
        -- TODO [ODS] This regexp is also filtering wrong values like '21617dac-3674-4490-bc05-995c01a3b19e'
        -- We implemented it here because of ODS Migration, but the rule must be rewritten
        RLIKE(CAST(id_lead AS VARCHAR(24)), '(^\\d+)')
    UNION
    SELECT
        CAST(REGEXP_EXTRACT(id_lead, '(^\\d+)') AS BIGINT) AS id_lead,
        NULL AS id_firestore,
        NULL AS formfield_lead_uuid,
        1 AS rule_num,
        'referral' AS rule,
        ts_event,
        utm_campaign,
        utm_medium,
        utm_source,
        utm_content,
        utm_term,
        app_type AS platform,
        referring_domain,
        region,
        city,
        uuid
    FROM
        datalake_amplitude_clean.205027_referral_form_discarded_events
    WHERE
        -- TODO [ODS] This regexp is also filtering wrong values like '21617dac-3674-4490-bc05-995c01a3b19e'
        -- We implemented it here because of ODS Migration, but the rule must be rewritten
        RLIKE(CAST(id_lead AS VARCHAR(24)), '(^\\d+)')
),
app_183047_form_submitted_events AS (
    SELECT
        formfield_lead_uuid,
        event_properties,
        ts_event,
        utm_campaign,
        utm_medium,
        utm_source,
        utm_content,
        utm_term,
        app_type AS platform,
        referring_domain,
        region,
        city,
        uuid
    FROM
        datalake_amplitude_clean.183047_lead_form_submitted_events
    WHERE
        formfield_lead_uuid IS NOT NULL
    UNION
    SELECT
        formfield_lead_uuid,
        event_properties,
        ts_event,
        utm_campaign,
        utm_medium,
        utm_source,
        utm_content,
        utm_term,
        app_type AS platform,
        referring_domain,
        region,
        city,
        uuid
    FROM
        datalake_amplitude_clean.183047_price_suggestion_form_submitted_events
    WHERE
        formfield_lead_uuid IS NOT NULL
    UNION
    SELECT
        formfield_lead_uuid,
        event_properties,
        ts_event,
        utm_campaign,
        utm_medium,
        utm_source,
        utm_content,
        utm_term,
        app_type AS platform,
        referring_domain,
        region,
        city,
        uuid
    FROM
        datalake_amplitude_clean.183047_price_suggestion_sale_form_submitted_events
    WHERE
        formfield_lead_uuid IS NOT NULL
),
app_ALL_lead_referred_events AS (
    SELECT
        CAST(REGEXP_EXTRACT(GET_JSON_OBJECT(event_properties , '$.Lead_id'), '(^\\d+)') AS BIGINT) AS id_lead,
        NULL AS id_firestore,
        NULL AS formfield_lead_uuid,
        2 AS rule_num,
        'referral_2' AS rule,
        ts_event,
        GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS utm_campaign,
        GET_JSON_OBJECT(user_properties, '$.utm_medium') AS utm_medium,
        GET_JSON_OBJECT(user_properties, '$.utm_source') AS utm_source,
        GET_JSON_OBJECT(user_properties, '$.utm_content') AS utm_content,
        GET_JSON_OBJECT(user_properties, '$.utm_term') AS utm_term,
        GET_JSON_OBJECT(user_properties, '$.platform') AS platform,
        GET_JSON_OBJECT(user_properties, '$.referring_domain') AS referring_domain,
        region,
        city,
        uuid
    FROM
        datalake_amplitude_clean.events
    WHERE
        event_type IN ('Affiliate-Lead_referred', 'Refer-Lead_referred' )
        AND RLIKE(GET_JSON_OBJECT(event_properties , '$.Lead_id'), '(^\\d+)')
),
app_183047_all_events_firestore AS (
    SELECT
        NULL AS id_lead,
        COALESCE(rene.id, GET_JSON_OBJECT(user_properties , '$.lead_firestore_id')) AS id_firestore,
        NULL AS formfield_lead_uuid,
        3 AS rule_num,
        'firestore' AS rule,
        ts_event,
        GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS utm_campaign,
        GET_JSON_OBJECT(user_properties, '$.utm_medium') AS utm_medium,
        GET_JSON_OBJECT(user_properties, '$.utm_source') AS utm_source,
        GET_JSON_OBJECT(user_properties, '$.utm_content') AS utm_content,
        GET_JSON_OBJECT(user_properties, '$.utm_term') AS utm_term,
        GET_JSON_OBJECT(user_properties, '$.platform') AS platform,
        GET_JSON_OBJECT(user_properties, '$.referring_domain') AS referring_domain,
        region,
        city,
        uuid
    FROM
        datalake_amplitude_clean.events
    LEFT JOIN datalake_rene_descartes_clean.house_lead rene
        ON rene.id_external_reference = GET_JSON_OBJECT(user_properties , '$.lead_firestore_id')
    -- On 2021-07-15 a change was made by the Product Team,
    -- the firestore_id is no longer being inserted on datalake_amplitude_clean_prod.events,
    -- but in datalake_rene_descartes_clean_prod.house_lead
        AND DATE(ts_event) >= DATE('2021-07-15')
    WHERE
        id_app = 183047
        AND GET_JSON_OBJECT(user_properties, '$.lead_firestore_id') IS NOT NULL
),
app_183047_form_submitted_events_rene AS (
    SELECT
        NULL AS id_lead,
        NULL AS id_firestore,
        COALESCE(rene.id, app_183047_form_submitted_events.formfield_lead_uuid, '') AS formfield_lead_uuid,
        4 AS rule_num,
        'formfield' AS rule,
        ts_event,
        utm_campaign,
        utm_medium,
        utm_source,
        utm_content,
        utm_term,
        platform,
        referring_domain,
        region,
        city,
        uuid
    FROM
        app_183047_form_submitted_events
    LEFT JOIN datalake_rene_descartes_clean.house_lead rene
        ON rene.id_external_reference = app_183047_form_submitted_events.formfield_lead_uuid
        -- On 2021-07-15 a change was made by the Product Team,
        -- the ep_formfield_lead_uuid is no longer being inserted on datalake_amplitude_clean_prod.events
        -- but in datalake_rene_descartes_clean_prod.house_lead
            AND DATE(app_183047_form_submitted_events.ts_event) >= DATE('2021-07-15')
),
lead_events_union AS (
    SELECT
        *,
        RANK() OVER(PARTITION BY id_lead ORDER BY ts_event) AS rn
    FROM app_205027_referral_form_events
    UNION
    SELECT
        *,
        RANK() OVER(PARTITION BY id_lead ORDER BY ts_event) AS rn
    FROM app_ALL_lead_referred_events
    UNION
    SELECT
        *,
        RANK() OVER(PARTITION BY id_firestore ORDER BY ts_event) AS rn
    FROM app_183047_all_events_firestore
    UNION
    SELECT
        *,
        RANK() OVER(PARTITION BY formfield_lead_uuid ORDER BY ts_event DESC) AS rn
    FROM app_183047_form_submitted_events_rene
)
SELECT
    id_lead,
    id_firestore,
    formfield_lead_uuid,
    COALESCE(uuid, '') AS uuid,
    rule_num,
    COALESCE(platform, '') AS platform,
    COALESCE(referring_domain, '') AS referring_domain,
    COALESCE(region, '') AS region,
    COALESCE(city, '') AS city,
    SUBSTR(COALESCE(utm_campaign,''), 1, 250) AS utm_campaign,
    SUBSTR(COALESCE(utm_medium,''), 1, 250) AS utm_medium,
    SUBSTR(COALESCE(utm_source,''), 1, 250) AS utm_source,
    SUBSTR(COALESCE(utm_content,''), 1, 250) AS utm_content,
    SUBSTR(COALESCE(utm_term,''), 1, 250) AS utm_term,
    ts_event
FROM
    lead_events_union
WHERE
    rn = 1