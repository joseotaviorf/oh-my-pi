SELECT
    id_intent,
    contact_id AS id_contact,
    origin,
    supply_source,
    detailed_route,
    experiments,
    ts_created,
    YEAR(ts_created) AS year,
    MONTH(ts_created) AS month,
    DAY(ts_created) AS day
FROM
    datalake_rene_descartes_raw.lead_intent
