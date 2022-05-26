SELECT
    id AS id_owner,
    user_id AS id_user,
    email,
    first_name,
    last_name,
    teams,
    archived AS is_archived,
    archived_at AS ts_archived,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hubspot_raw.owner
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}