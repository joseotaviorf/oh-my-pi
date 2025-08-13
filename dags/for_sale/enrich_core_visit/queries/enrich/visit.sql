WITH vsl AS (
    SELECT
        id_visit,
        event_type AS last_event_type
    FROM
        datalake_ebdb_test_clean.visit_status_log
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_visit ORDER BY ts_created DESC) = 1
)
SELECT
    v.id,
    v.id_house,
    v.id_visitor,
    v.id_agent,
    v.code,
    v.status,
    v.computed_status,
    v.business_context,
    vsl.last_event_type,
    v.dt_visit,
    v.dt_request,
    v.ts_created,
    v.ts_updated
FROM
    datalake_ebdb_test_clean.visit AS v
LEFT JOIN
    vsl
        ON vsl.id_visit = v.id