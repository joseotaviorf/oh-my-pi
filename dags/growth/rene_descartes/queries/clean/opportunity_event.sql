SELECT
    id AS id_opportunity_event,
    opportunity_id AS id_opportunity,
    contact_id AS id_contact,
    trigger_event_id AS id_trigger_event,
    entity_id AS id_entity,
    product,
    conversion_status,
    funnel_step,
    type AS event_type,
    trigger_event,
    entity,
    ts_created,
    YEAR(ts_created) AS year,
    MONTH(ts_created) AS month,
    DAY(ts_created) AS day
FROM
    datalake_rene_descartes_raw.opportunity_event
