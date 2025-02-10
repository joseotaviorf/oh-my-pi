SELECT
    id,
    house_lead_id AS id_house_lead,
    business_context,
    reason,
    origin,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rene_descartes_cdc_raw.lead_rejection
