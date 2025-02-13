SELECT
    id,
    house_lead_id AS id_house_lead,
    business_context,
    reason,
    origin,
    created_at AS ts_created,
    updated_at AS ts_updated,
    YEAR(updated_at) AS year,
    MONTH(updated_at) AS month,
    DAY(updated_at) AS day
FROM
    datalake_rene_descartes_raw.lead_rejection
