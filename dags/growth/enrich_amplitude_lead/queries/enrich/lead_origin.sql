WITH app_205027_referral_form_events AS (
    SELECT
        id_lead::INTEGER AS id_lead,
        NULL AS id_firestore,
        NULL AS formfield_lead_uuid,
        1 AS rule_num,
        'referral' AS rule,
        country AS user_country,
        GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
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
        id_lead::INTEGER IS NOT NULL
    UNION
    SELECT
        id_lead::INTEGER AS id_lead,
        NULL AS id_firestore,
        NULL AS formfield_lead_uuid,
        1 AS rule_num,
        'referral' AS rule,
        country AS user_country,
        GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
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
        id_lead::INTEGER IS NOT NULL
),
app_183047_form_submitted_events AS (
    SELECT
        formfield_lead_uuid,
        event_properties,
        country AS user_country,
        GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
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
        country AS user_country,
        GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
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
        country AS user_country,
        GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
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
        ep_id_lead AS id_lead,
        NULL AS id_firestore,
        NULL AS formfield_lead_uuid,
        2 AS rule_num,
        'referral_2' AS rule,
        country AS user_country,
        GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
        ts_event,
        up_utm_campaign AS utm_campaign,
        up_utm_medium AS utm_medium,
        up_utm_source AS utm_source,
        up_utm_content AS utm_content,
        up_utm_term AS utm_term,
        up_platform AS platform,
        up_referring_domain AS referring_domain,
        region,
        city,
        uuid
    FROM
        datalake_amplitude_clean.160023_affiliate_lead_referred_events
    WHERE
        ep_id_lead::INTEGER IS NOT NULL

    UNION

    SELECT
        ep_id_lead AS id_lead,
        NULL AS id_firestore,
        NULL AS formfield_lead_uuid,
        2 AS rule_num,
        'referral_2' AS rule,
        country AS user_country,
        GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
        ts_event,
        up_utm_campaign AS utm_campaign,
        up_utm_medium AS utm_medium,
        up_utm_source AS utm_source,
        up_utm_content AS utm_content,
        up_utm_term AS utm_term,
        up_platform AS platform,
        up_referring_domain AS referring_domain,
        region,
        city,
        uuid
    FROM
        datalake_amplitude_clean.155696_refer_lead_referred_events
    WHERE
        ep_id_lead::INTEGER IS NOT NULL

    UNION

    SELECT
        ep_id_lead AS id_lead,
        NULL AS id_firestore,
        NULL AS formfield_lead_uuid,
        2 AS rule_num,
        'referral_2' AS rule,
        country AS user_country,
        GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
        ts_event,
        up_utm_campaign AS utm_campaign,
        up_utm_medium AS utm_medium,
        up_utm_source AS utm_source,
        up_utm_content AS utm_content,
        up_utm_term AS utm_term,
        up_platform AS platform,
        up_referring_domain AS referring_domain,
        region,
        city,
        uuid
    FROM
        datalake_amplitude_clean.155697_refer_lead_referred_events
    WHERE
        ep_id_lead::INTEGER IS NOT NULL
),
user_attribution_exploded AS (
    SELECT
        FROM_JSON(user_properties,'
                country STRING,
                lead_firestore_id STRING,
                utm_campaign STRING,
                utm_medium STRING,
                utm_source STRING,
                utm_content STRING,
                utm_term STRING,
                platform STRING,
                referring_domain STRING') AS user_properties,
        country AS user_country,
        ts_event,
        region,
        city,
        uuid
    FROM
        datalake_amplitude_clean.events
    WHERE
        id_app = 183047
),
app_183047_all_events_firestore AS (
    SELECT
        NULL AS id_lead,
        COALESCE(rene.id, user_properties.lead_firestore_id) AS id_firestore,
        NULL AS formfield_lead_uuid,
        3 AS rule_num,
        'firestore' AS rule,
        user_country,
        TRIM(user_properties.country) AS country_code,
        ts_event,
        TRIM(user_properties.utm_campaign) AS utm_campaign,
        TRIM(user_properties.utm_medium) AS utm_medium,
        TRIM(user_properties.utm_source) AS utm_source,
        TRIM(user_properties.utm_content) AS utm_content,
        TRIM(user_properties.utm_term) AS utm_term,
        TRIM(user_properties.platform) AS platform,
        TRIM(user_properties.referring_domain) AS referring_domain,
        region,
        city,
        uuid
    FROM
        user_attribution_exploded
    LEFT JOIN datalake_rene_descartes_clean.house_lead rene
        ON rene.id_external_reference = user_properties.lead_firestore_id
    -- On 2021-07-15 a change was made by the Product Team,
    -- the firestore_id is no longer being inserted on datalake_amplitude_clean_prod.events,
    -- but in datalake_rene_descartes_clean_prod.house_lead
        AND DATE(ts_event) >= DATE('2021-07-15')
    WHERE
        user_properties.lead_firestore_id IS NOT NULL
),
app_183047_form_submitted_events_rene AS (
    SELECT
        NULL AS id_lead,
        NULL AS id_firestore,
        COALESCE(rene.id, app_183047_form_submitted_events.formfield_lead_uuid, '') AS formfield_lead_uuid,
        4 AS rule_num,
        'formfield' AS rule,
        user_country,
        country_code,
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
app_183047_intro_page_viewed_events AS(
  SELECT
    CAST(GET_JSON_OBJECT(event_properties, '$.lead_id') AS BIGINT) AS id_lead,
    NULL AS id_firestore,
    NULL AS formfield_lead_uuid,
    5 AS rule_num,
    'opr' AS rule,
    country AS user_country,
    GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
    ts_event,
    up_utm_campaign AS utm_campaign,
    up_utm_medium AS utm_medium,
    up_utm_source AS utm_source,
    up_utm_content AS utm_content,
    up_utm_term AS utm_term,
    CAST(GET_JSON_OBJECT(user_properties , '$.platform') AS STRING) AS platform,
    CAST(GET_JSON_OBJECT(user_properties , '$.referring_domain') AS STRING) AS referring_domain,
    region,
    city,
    uuid
  FROM
    datalake_amplitude_clean.183047_intro_page_viewed_events
  WHERE
    GET_JSON_OBJECT(event_properties, '$.lead_id') IS NOT NULL
),
app_183047_property_details_page_viewed_events AS (
  SELECT
    event_properties:lead_id::BIGINT AS id_lead,
    NULL AS id_firestore,
    NULL AS formfield_lead_uuid,
    6 AS rule_num,
    'opr' AS rule,
    country AS user_country,
    user_properties:country AS country_code,
    ts_event,
    up_utm_campaign AS utm_campaign,
    up_utm_medium AS utm_medium,
    up_utm_source AS utm_source,
    up_utm_content AS utm_content,
    up_utm_term AS utm_term,
    user_properties:platform::STRING AS platform,
    user_properties:referring_domain::STRING AS referring_domain,
    region,
    city,
    uuid
  FROM
    datalake_amplitude_clean.183047_property_details_page_viewed_events
  WHERE
    event_properties:lead_id IS NOT NULL
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
    UNION
    SELECT
        *,
        RANK() OVER(PARTITION BY id_lead ORDER BY ts_event DESC) AS rn
    FROM app_183047_intro_page_viewed_events
    UNION
    SELECT
        *,
        RANK() OVER(PARTITION BY id_lead ORDER BY ts_event DESC) AS rn
    FROM app_183047_property_details_page_viewed_events
)
SELECT
    id_lead,
    id_firestore,
    formfield_lead_uuid,
    COALESCE(uuid, '') AS uuid,
    country_code,
    user_country,
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
