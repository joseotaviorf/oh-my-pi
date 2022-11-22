SELECT
    id,
    name,
    creator_id,
    is_users_root,
    is_personal,
    is_personal_descendant,
    path,
    year,
    month,
    day
FROM
    datalake_looker_raw.folders
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
