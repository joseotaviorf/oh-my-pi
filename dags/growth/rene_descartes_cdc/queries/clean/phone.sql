SELECT
    id,
    owner_id AS id_owner,
    phone_nr AS phone_number,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rene_descartes_cdc_raw.phone
