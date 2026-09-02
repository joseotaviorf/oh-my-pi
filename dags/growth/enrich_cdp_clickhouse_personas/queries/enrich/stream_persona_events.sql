WITH transactional_base AS (
    SELECT
        transactional.id_event,
        transactional.id_user,
        transactional.id_person AS uuid_person,
        COALESCE(
            GET_JSON_OBJECT(transactional.event_properties, '$.owner_email'),
            GET_JSON_OBJECT(transactional.user_properties, '$.email')
        ) AS email,
        COALESCE(
            GET_JSON_OBJECT(transactional.event_properties, '$.owner_phone'),
            GET_JSON_OBJECT(transactional.user_properties, '$.phone')
        ) AS phone,
        transactional.application,
        transactional.event_name,
        transactional.journey_step,
        CASE
            WHEN transactional.event_name IN (
                'rene_lead_processed',
                'rene_lead_converted'
            ) THEN 'OWNER_PROSPECT'
            WHEN transactional.application = 'tenant-app' THEN 'TENANT_PROSPECT'
            WHEN transactional.application = 'owner-app' THEN 'OWNER'
        END AS persona,
        transactional.event_properties,
        true AS is_active,
        transactional.ts_event,
        transactional.ts_egw AS ts_egw_updated_at,
        transactional.ts_egw AS ts_ingested_at
    FROM
        datalake_cdp_clean.transactional AS transactional
    WHERE
        transactional.ts_egw >= TIMESTAMP('{load_start_date}')
        AND transactional.ts_egw <= TIMESTAMP('{load_end_date}')
        AND (
            transactional.event_name IN (
                'answer_confirmed',
                'answer_pending',
                'answer_rejected',
                'visit_canceled',
                'visit_confirmed',
                'visit_contested',
                'visit_fitted',
                'visit_request_canceled',
                'visit_requested',
                'visit_rescheduled',
                'visit_scheduled',
                'visit_unsuccessful',
                'rene_lead_processed',
                'rene_lead_converted'
            )
            OR transactional.application IN ('tenant-app', 'owner-app')
        )
),
visit_events AS (
    SELECT
        transactional.id_event,
        transactional.id_user,
        GET_JSON_OBJECT(
            transactional.event_properties,
            '$.visit.visitorId'
        ) AS id_prospect,
        GET_JSON_OBJECT(
            transactional.event_properties,
            '$.authorUserRole'
        ) AS author_user_role,
        GET_JSON_OBJECT(
            transactional.event_properties,
            '$.schedule.businessContext'
        ) AS business_context,
        FROM_JSON(
            transactional.event_properties,
            'STRUCT<visitors:ARRAY<STRUCT<type:STRING, userId:BIGINT>>>'
        ) AS visitors,
        transactional.journey_step,
        transactional.is_active,
        transactional.ts_event,
        transactional.ts_egw_updated_at,
        transactional.ts_ingested_at
    FROM
        transactional_base AS transactional
    WHERE
        transactional.event_name IN (
            'answer_confirmed',
            'answer_pending',
            'answer_rejected',
            'visit_canceled',
            'visit_confirmed',
            'visit_contested',
            'visit_fitted',
            'visit_request_canceled',
            'visit_requested',
            'visit_rescheduled',
            'visit_scheduled',
            'visit_unsuccessful'
        )
),
visit_exploded AS (
    SELECT
        visit.id_event,
        CASE
            WHEN visit.author_user_role = 'DEMAND' THEN
                COALESCE(CAST(visit.id_prospect AS BIGINT), visit.id_user)
            WHEN
                visit.author_user_role = 'SUPPLY'
                AND visitor.type = 'Landlord'
                THEN visitor.userId
        END AS id_user,
        CASE
            WHEN
                visit.author_user_role = 'DEMAND'
                AND visit.business_context = 'RENT'
                THEN 'TENANT_PROSPECT'
            WHEN
                visit.author_user_role = 'DEMAND'
                AND visit.business_context = 'SALE'
                THEN 'BUYER_PROSPECT'
            WHEN visit.author_user_role = 'SUPPLY' THEN 'OWNER'
        END AS persona,
        visit.journey_step,
        visit.is_active,
        visit.ts_event,
        visit.ts_egw_updated_at,
        visit.ts_ingested_at
    FROM
        visit_events AS visit
    LATERAL VIEW OUTER
        EXPLODE(visit.visitors.visitors) AS visitor
),
visit_person AS (
    SELECT
        visit.id_event,
        visit.id_user,
        person.uuid_person,
        visit.persona,
        visit.journey_step,
        visit.is_active,
        visit.ts_event,
        visit.ts_egw_updated_at,
        visit.ts_ingested_at
    FROM
        visit_exploded AS visit
    LEFT JOIN
        datalake_ebdb_clean.user AS person
            ON person.id = visit.id_user
),
identity_resolved AS (
    SELECT
        transactional.id_event,
        CAST(person.id_user AS BIGINT) AS id_user,
        person.uuid_person,
        transactional.persona,
        transactional.journey_step,
        transactional.is_active,
        transactional.ts_event,
        transactional.ts_egw_updated_at,
        transactional.ts_ingested_at
    FROM
        transactional_base AS transactional
    INNER JOIN
        datalake_cdp.person AS person
            ON transactional.persona = 'OWNER_PROSPECT'
            AND person.phone_number = transactional.phone
    UNION
    SELECT
        transactional.id_event,
        CAST(person.id_user AS BIGINT) AS id_user,
        person.uuid_person,
        transactional.persona,
        transactional.journey_step,
        transactional.is_active,
        transactional.ts_event,
        transactional.ts_egw_updated_at,
        transactional.ts_ingested_at
    FROM
        transactional_base AS transactional
    INNER JOIN
        datalake_cdp.person AS person
            ON transactional.persona = 'OWNER_PROSPECT'
            AND person.email = transactional.email
),
unified AS (
    SELECT
        transactional.id_event,
        transactional.id_user,
        transactional.uuid_person,
        transactional.persona,
        transactional.journey_step,
        transactional.is_active,
        transactional.ts_event,
        transactional.ts_egw_updated_at,
        transactional.ts_ingested_at
    FROM
        transactional_base AS transactional
    UNION ALL
    SELECT
        visit.id_event,
        visit.id_user,
        visit.uuid_person,
        visit.persona,
        visit.journey_step,
        visit.is_active,
        visit.ts_event,
        visit.ts_egw_updated_at,
        visit.ts_ingested_at
    FROM
        visit_person AS visit
    UNION ALL
    SELECT
        resolved.id_event,
        resolved.id_user,
        resolved.uuid_person,
        resolved.persona,
        resolved.journey_step,
        resolved.is_active,
        resolved.ts_event,
        resolved.ts_egw_updated_at,
        resolved.ts_ingested_at
    FROM
        identity_resolved AS resolved
),
ranked AS (
    SELECT
        SHA2(CONCAT(id_user, persona), 512) AS id_persona_event,
        id_user,
        uuid_person,
        persona,
        journey_step AS last_journey_step,
        is_active,
        ts_event AS ts_updated,
        ts_egw_updated_at,
        ts_ingested_at,
        id_event,
        ROW_NUMBER() OVER (
            PARTITION BY id_user, persona
            ORDER BY
                ts_event DESC,
                ts_egw_updated_at DESC,
                ts_ingested_at DESC,
                id_event DESC
        ) AS row_number
    FROM
        unified
    WHERE
        id_user IS NOT NULL
        AND persona IS NOT NULL
)
SELECT
    id_persona_event,
    id_user,
    uuid_person,
    persona,
    last_journey_step,
    is_active,
    CAST(NULL AS TIMESTAMP) AS ts_started,
    ts_updated,
    CAST(NULL AS TIMESTAMP) AS ts_ended,
    CURRENT_TIMESTAMP() AS ts_load,
    ts_ingested_at,
    YEAR(ts_updated) AS year,
    MONTH(ts_updated) AS month,
    DAY(ts_updated) AS day
FROM
    ranked
WHERE
    row_number = 1
