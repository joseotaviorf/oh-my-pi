SELECT
    id,
    owner_id AS id_owner,
    phone_nr AS phone_number,
    created_at AS ts_created,
    updated_at AS ts_updated,
    YEAR(updated_at) AS year,
    MONTH(updated_at) AS month,
    DAY(updated_at) as day
FROM
    datalake_rene_descartes_raw.phone
