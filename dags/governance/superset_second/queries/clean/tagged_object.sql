SELECT 
    id,
    tag_id AS id_tag,
    object_id AS id_object,
    created_by_fk AS id_user_created,
    changed_by_fk AS id_user_changed,
    object_type,
    created_on AS ts_created,
    changed_on AS ts_changed,
    year,
    month,
    day
FROM datalake_superset_raw.tagged_object
WHERE year = {year} AND month = {month} AND day = {day}