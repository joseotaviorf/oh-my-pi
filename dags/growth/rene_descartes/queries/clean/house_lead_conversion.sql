 SELECT
    id,
    house_lead_id AS id_lead,
    property_id AS id_house,
    created_at AS ts_created,
    updated_at AS ts_updated,
    YEAR(updated_at) AS year,
    MONTH(updated_at) AS month,
    DAY(updated_at) AS day
FROM
    datalake_rene_descartes_raw.house_lead_conversion
