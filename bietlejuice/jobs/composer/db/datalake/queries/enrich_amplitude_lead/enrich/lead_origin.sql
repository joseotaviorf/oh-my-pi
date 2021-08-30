WITH app_205027 AS (
    SELECT
        id_lead,
        ts_event,
        utm_campaign,
        utm_medium,
        utm_source,
        utm_content,
        utm_term,
        app_type,
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
        id_lead,
        ts_event,
        utm_campaign,
        utm_medium,
        utm_source,
        utm_content,
        utm_term,
        app_type,
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
app_183047 AS (
    SELECT
        formfield_lead_uuid,
        event_properties,
        ts_event,
        utm_campaign,
        utm_medium,
        utm_source,
        utm_content,
        utm_term,
        app_type,
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
        app_type,
        referring_domain,
        region,
        city,
        uuid
    FROM
        datalake_amplitude_clean.183047_price_suggestion_form_submitted_events
    WHERE
        formfield_lead_uuid IS NOT NULL
),
prep_ref AS (
    select
        -- TODO [ODS] The following rule is extracting numeric chars from the column id_lead,
        --  due to incorrect filtering in the 1st CTE, this rule is extracting fake id_lead's:
        -- e.g.: '21617dac-3674-4490-bc05-995c01a3b19e' wrongly filtered in the 1st CTE is
        --       being transformed to id_lead 21617, but it is not a real id_lead from this record
        CAST(
            REGEXP_EXTRACT(
                            COALESCE(CAST(id_lead AS VARCHAR(24)), '')
                            , '(^\\d+)'
                            ) AS BIGINT
            ) AS id_lead,
        NULL AS id_firestore,
        NULL AS formfield_lead_uuid,
        1 AS rule_num,
        'referral' AS RULE,
        ts_event,
        COALESCE(CAST(utm_campaign AS VARCHAR(255)), '') AS utm_campaign,
        COALESCE(CAST(utm_medium AS VARCHAR(255)), '') AS utm_medium,
        COALESCE(CAST(utm_source AS VARCHAR(255)), '') AS utm_source,
        COALESCE(CAST(utm_content AS VARCHAR(255)), '') AS utm_content,
        COALESCE(CAST(utm_term AS VARCHAR(255)), '') AS utm_term,
        COALESCE(CAST(app_type AS VARCHAR(255)), '') AS platform,
        COALESCE(CAST(referring_domain AS VARCHAR(255)), '') AS referring_domain,
        COALESCE(region, '') AS region,
        COALESCE(city, '') AS city,
        COALESCE(uuid, '') AS uuid
    FROM
        app_205027
),
prep_ref_2 AS (
    SELECT
        CAST(REGEXP_EXTRACT(
            COALESCE(CAST(GET_JSON_OBJECT(event_properties , '$.Lead_id') AS VARCHAR(255)), '')
            , '(^\\d+)') AS BIGINT) AS id_lead,
        NULL AS id_firestore,
        NULL AS formfield_lead_uuid,
        2 AS rule_num,
        'referral_2' AS rule,
        ts_event,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS VARCHAR(255)) AS utm_campaign,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_medium') AS VARCHAR(255)) AS utm_medium,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_source') AS VARCHAR(255)) AS utm_source,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_content') AS VARCHAR(255)) AS utm_content,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_term') AS VARCHAR(255)) AS utm_term,
        CAST(GET_JSON_OBJECT(user_properties, '$.platform') AS VARCHAR(255)) AS platform,
        CAST(GET_JSON_OBJECT(user_properties, '$.referring_domain') AS VARCHAR(255)) AS referring_domain,
        COALESCE(region, '') AS region,
        COALESCE(city, '') AS city,
        COALESCE(uuid, '') AS uuid
    FROM
        datalake_amplitude_clean.events
    WHERE
        event_type IN ('Affiliate-Lead_referred', 'Refer-Lead_referred' )
        AND RLIKE(CAST(GET_JSON_OBJECT(event_properties , '$.Lead_id') AS VARCHAR(255)), '(^\\d+)')
),
prep_firestore_tmp AS (
    SELECT
        NULL AS id_lead,
        COALESCE(CAST(GET_JSON_OBJECT(user_properties , '$.lead_firestore_id') AS VARCHAR(255)), '') AS id_firestore,
        NULL AS formfield_lead_uuid,
        3 AS rule_num,
        'firestore' AS rule,
        ts_event,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS VARCHAR(255)) AS utm_campaign,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_medium') AS VARCHAR(255)) AS utm_medium,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_source') AS VARCHAR(255)) AS utm_source,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_content') AS VARCHAR(255)) AS utm_content,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_term') AS VARCHAR(255)) AS utm_term,
        CAST(GET_JSON_OBJECT(user_properties, '$.platform') AS VARCHAR(255)) AS platform,
        CAST(GET_JSON_OBJECT(user_properties, '$.referring_domain') AS VARCHAR(255)) AS referring_domain,
        COALESCE(region, '') AS region,
        COALESCE(city, '') AS city,
        COALESCE(uuid, '') AS uuid
    FROM
        datalake_amplitude_clean.events
    WHERE
        id_app = 183047
        AND GET_JSON_OBJECT(user_properties, '$.lead_firestore_id') IS NOT NULL
),
prep_firestore AS (
    SELECT
        id_lead,
        COALESCE(rene.id, prep_firestore_tmp.id_firestore) AS id_firestore,
        formfield_lead_uuid,
        rule_num,
        rule,
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
        prep_firestore_tmp
    LEFT JOIN datalake_rene_descartes_clean.house_lead rene
        ON rene.id_external_reference = prep_firestore_tmp.id_firestore
            AND DATE(ts_event) >= DATE('2021-07-15')
),
prep_form AS (
    SELECT
        NULL AS id_lead,
        NULL AS id_firestore,
        COALESCE(CAST(formfield_lead_uuid AS VARCHAR(255)), '') AS formfield_lead_uuid,
        4 AS rule_num,
        'formfield' AS RULE,
        ts_event,
        COALESCE(CAST(utm_campaign AS VARCHAR(255)), '') AS utm_campaign,
        COALESCE(CAST(utm_medium AS VARCHAR(255)), '') AS utm_medium,
        COALESCE(CAST(utm_source AS VARCHAR(255)), '') AS utm_source,
        COALESCE(CAST(utm_content AS VARCHAR(255)), '') AS utm_content,
        COALESCE(CAST(utm_term AS VARCHAR(255)), '') AS utm_term,
        COALESCE(CAST(app_type AS VARCHAR(255)), '') AS platform,
        COALESCE(CAST(referring_domain AS VARCHAR(255)), '') AS referring_domain,
        COALESCE(region, '') AS region,
        COALESCE(city, '') AS city,
        COALESCE(uuid, '') AS uuid
    FROM
        app_183047
),
t_all AS (
    SELECT
        *,
        RANK() OVER(PARTITION BY id_lead ORDER BY ts_event) AS rn
    FROM prep_ref
    UNION
    SELECT
        *,
        RANK() OVER(PARTITION BY id_lead ORDER BY ts_event) AS rn
    FROM prep_ref_2
    UNION
    SELECT
        *,
        RANK() OVER(PARTITION BY id_firestore ORDER BY ts_event) AS rn
    FROM prep_firestore
    UNION
    SELECT
        *,
        RANK() OVER(PARTITION BY formfield_lead_uuid ORDER BY ts_event DESC) AS rn
    FROM prep_form
)
SELECT
    id_lead,
    id_firestore,
    formfield_lead_uuid,
    uuid,
    rule_num,
    platform,
    referring_domain,
    region,
    city,
    SUBSTR(utm_campaign, 1, 250) AS utm_campaign,
    SUBSTR(utm_medium, 1, 250) AS utm_medium,
    SUBSTR(utm_source, 1, 250) AS utm_source,
    SUBSTR(utm_content, 1, 250) AS utm_content,
    SUBSTR(utm_term, 1, 250) AS utm_term,
    ts_event
FROM
    t_all
WHERE
    rn = 1