SELECT
    id_rejection,
    lead_id AS id_lead,
    activity_id AS id_activity,
    supply_source,
    business_context,
    funnel_step,
    discard_reason,
    discard_rule,
    ts_created,
    YEAR(ts_created) AS year,
    MONTH(ts_created) AS month,
    DAY(ts_created) AS day
FROM
    datalake_rene_descartes_raw.supply_rejection
