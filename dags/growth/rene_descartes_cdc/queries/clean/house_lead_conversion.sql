 SELECT
    id,
    house_lead_id AS id_lead,
    property_id AS id_house,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rene_descartes_cdc_raw.house_lead_conversion
