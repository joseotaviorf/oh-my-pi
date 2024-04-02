SELECT 
    id,
    created_by_fk AS id_user_created,
    changed_by_fk AS id_user_changed,
    "name" AS tag_name,
    "type",
    "description",
    created_on AS ts_created,
    changed_on AS ts_changed,
    year,
    month,
    day
FROM datalake_superset_raw.tag
WHERE year = {year} AND month = {month} AND day = {day}