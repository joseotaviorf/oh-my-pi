SELECT
    id,
    key_location_preference_id AS id_key_location_preference,
    author_user_type,
    author_user_change_identifier,
    event_log_type,
    channel,
    description,
    created_at AS ts_created
FROM
    datalake_rental_management_raw.key_location_preference_log
