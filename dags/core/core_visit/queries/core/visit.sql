WITH vsl_last_event AS (
    SELECT
        id_visit,
        event_type AS last_event_type
    FROM
        datalake_ebdb_test_clean.visit_status_log
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_visit ORDER BY ts_created DESC) = 1
),
all_events AS (
    SELECT
        id_visit,
        MAX(CASE WHEN event_type IN ('VISIT_REQUEST_CANCELED', 'VISIT_CANCELED') THEN reason END) AS cancellation_reason,
        MAX(CASE WHEN event_type = 'VISIT_REQUESTED' THEN ts_created END) AS ts_visit_requested,
        MAX(CASE WHEN event_type = 'VISIT_CONFIRMED' THEN ts_created END) AS ts_visit_confirmed,
        MAX(CASE WHEN event_type = 'VISIT_DONE' THEN ts_created END) AS ts_visit_done,
        MAX(CASE WHEN event_type IN ('VISIT_REQUEST_CANCELED', 'VISIT_CANCELED') THEN ts_created END) AS ts_visit_canceled,
        MAX(CASE WHEN event_type = 'VISIT_UNSUCCESSFUL' THEN ts_created END) AS ts_visit_unsuccessful
    FROM
        datalake_ebdb_test_clean.visit_status_log
    GROUP BY 1
)
SELECT
    SHA2(CONCAT_WS("||", 'VISIT', v.id), 256) AS sk_core_visit,
    v.id AS id_visit,
    v.id_house,
    v.id_visitor,
    COALESCE(u.id, h.id_user) AS id_owner,
    v.id_agent,
    v.code,
    v.status,
    v.computed_status,
    v.type,
    v.business_context,
    vsl.last_event_type,
    ae.cancellation_reason,
    v.is_fixed_agent,
    v.dt_visit,
    v.ts_visit,
    ae.ts_visit_requested,
    ae.ts_visit_confirmed,
    ae.ts_visit_done,
    ae.ts_visit_canceled,
    ae.ts_visit_unsuccessful,
    v.ts_created,
    v.ts_updated,
    NOW() AS ts_load
FROM
    datalake_ebdb_test_clean.visit AS v
LEFT JOIN
    vsl_last_event AS vsl
        ON vsl.id_visit = v.id
LEFT JOIN
    all_events AS ae
        ON ae.id_visit = v.id
LEFT JOIN
    datalake_ebdb_clean.house AS h
        ON h.id = v.id_house
LEFT JOIN
    datalake_ebdb_clean.house_listing_relation AS hl
        ON hl.id = v.id_house
        AND hl.related_as = 'PROPERTY_OWNER'
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON (u.id = hl.id_related
        OR u.uuid_person = hl.id_related)