SELECT
    id AS id_house,
    user_id AS id_user,
    external_id AS id_external,
    status,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    rent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_owner_fees_raw.house_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
