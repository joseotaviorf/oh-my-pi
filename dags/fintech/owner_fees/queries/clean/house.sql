SELECT
    id,
    user_id AS id_user,
    external_id AS id_external,
    status,
    rent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_owner_fees_raw.house
