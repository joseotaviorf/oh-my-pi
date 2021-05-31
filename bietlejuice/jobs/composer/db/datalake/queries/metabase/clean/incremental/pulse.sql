SELECT
    id,
    creator_id AS id_user_creator,
    collection_id AS id_collection,
    name,
    collection_position,
    alert_condition,
    archived AS is_archived,
    skip_if_empty AS is_skipped_if_empty,
    alert_first_only AS has_alert_if_first_only,
    alert_above_goal AS has_alert_if_above_goal,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_metabase_raw.pulse
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
