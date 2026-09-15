WITH transactional_base AS (
    SELECT
        txn.id_user,
        txn.id_person AS uuid_person,
        COALESCE(
            GET_JSON_OBJECT(txn.event_properties, '$.owner_email'),
            GET_JSON_OBJECT(txn.user_properties, '$.email')
        ) AS email,
        COALESCE(
            GET_JSON_OBJECT(txn.event_properties, '$.owner_phone'),
            GET_JSON_OBJECT(txn.user_properties, '$.phone')
        ) AS phone,
        txn.event_name,
        txn.journey_step,
        CASE
            WHEN txn.event_name IN (
                'rene_lead_processed',
                'rene_lead_converted'
            ) THEN 'OWNER_PROSPECT'
            WHEN txn.application = 'tenant-app' THEN 'TENANT_PROSPECT'
            WHEN txn.application = 'owner-app' THEN 'OWNER'
        END AS persona,
        txn.event_properties,
        TRUE AS is_active,
        txn.ts_event,
        YEAR(TO_DATE(txn.event_date)) AS year,
        MONTH(TO_DATE(txn.event_date)) AS month,
        DAY(TO_DATE(txn.event_date)) AS day
    FROM
        datalake_cdp_clean.transactional_events AS txn
    WHERE
        txn.event_date >= DATE_FORMAT(TO_DATE('{load_start_date}'), 'yyyy-MM-dd')
        AND txn.event_date <= DATE_FORMAT(TO_DATE('{load_end_date}'), 'yyyy-MM-dd')
        AND (
            txn.event_name IN (
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
            OR txn.application IN (
                'tenant-app',
                'owner-app'
            )
        )
),
visit_events AS (
    SELECT
        id_user,
        GET_JSON_OBJECT(
            event_properties,
            '$.visit.visitorId'
        ) AS id_prospect,
        GET_JSON_OBJECT(
            event_properties,
            '$.authorUserRole'
        ) AS author_user_role,
        GET_JSON_OBJECT(
            event_properties,
            '$.schedule.businessContext'
        ) AS business_context,
        FROM_JSON(
            event_properties,
            'STRUCT<visitors:ARRAY<STRUCT<type:STRING,userId:BIGINT>>>'
        ) AS visitors,
        journey_step,
        is_active,
        ts_event,
        year,
        month,
        day
    FROM
        transactional_base
    WHERE
        event_name IN (
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
        CASE
            WHEN visit_evt.author_user_role = 'DEMAND' THEN COALESCE(
                CAST(visit_evt.id_prospect AS BIGINT),
                CAST(visit_evt.id_user AS BIGINT)
            )
            WHEN visit_evt.author_user_role = 'SUPPLY'
                AND visitor.type = 'Landlord' THEN visitor.userId
        END AS id_user,
        CASE
            WHEN visit_evt.author_user_role = 'DEMAND'
                AND visit_evt.business_context = 'RENT' THEN 'TENANT_PROSPECT'
            WHEN visit_evt.author_user_role = 'DEMAND'
                AND visit_evt.business_context = 'SALE' THEN 'BUYER_PROSPECT'
            WHEN visit_evt.author_user_role = 'SUPPLY' THEN 'OWNER'
        END AS persona,
        visit_evt.journey_step,
        visit_evt.is_active,
        visit_evt.ts_event,
        visit_evt.year,
        visit_evt.month,
        visit_evt.day
    FROM
        visit_events AS visit_evt
    LATERAL VIEW OUTER
        EXPLODE(visit_evt.visitors.visitors) exploded AS visitor
),
visit_person AS (
    SELECT
        visit.id_user,
        ebdb_user.uuid_person,
        visit.persona,
        visit.journey_step,
        visit.is_active,
        visit.ts_event,
        visit.year,
        visit.month,
        visit.day
    FROM
        visit_exploded AS visit
    LEFT JOIN
        datalake_ebdb_clean.user AS ebdb_user
            ON ebdb_user.id = visit.id_user
),
idr_by_person AS (
    SELECT
        cdp_person.id_user,
        cdp_person.uuid_person,
        txn.persona,
        txn.journey_step,
        txn.is_active,
        txn.ts_event,
        txn.year,
        txn.month,
        txn.day
    FROM
        transactional_base AS txn
    INNER JOIN
        datalake_cdp.person AS cdp_person
            ON txn.persona = 'OWNER_PROSPECT'
            AND cdp_person.phone_number = txn.phone
    UNION
    SELECT
        cdp_person.id_user,
        cdp_person.uuid_person,
        txn.persona,
        txn.journey_step,
        txn.is_active,
        txn.ts_event,
        txn.year,
        txn.month,
        txn.day
    FROM
        transactional_base AS txn
    INNER JOIN
        datalake_cdp.person AS cdp_person
            ON txn.persona = 'OWNER_PROSPECT'
            AND cdp_person.email = txn.email
),
unifying AS (
    SELECT
        id_user,
        uuid_person,
        persona,
        journey_step,
        is_active,
        ts_event,
        year,
        month,
        day
    FROM
        transactional_base
    UNION ALL
    SELECT
        id_user,
        uuid_person,
        persona,
        journey_step,
        is_active,
        ts_event,
        year,
        month,
        day
    FROM
        visit_person
    UNION ALL
    SELECT
        id_user,
        uuid_person,
        persona,
        journey_step,
        is_active,
        ts_event,
        year,
        month,
        day
    FROM
        idr_by_person
),
ranked AS (
    SELECT
        SHA2(
            CONCAT(
                CAST(id_user AS STRING),
                persona
            ),
            512
        ) AS id_persona_event,
        id_user,
        uuid_person,
        persona,
        journey_step AS last_journey_step,
        is_active,
        ts_event AS ts_updated,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_user,
                persona
            ORDER BY
                ts_event DESC,
                year DESC,
                month DESC,
                day DESC
        ) AS row_number
    FROM
        unifying
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
    year,
    month,
    day
FROM
    ranked
WHERE
    row_number = 1
