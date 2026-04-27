SELECT
    id,
    managed_rental_id AS id_managed_rental,
    managed_rental_users_id AS id_managed_rental_users,
    author_user_type,
    author_user_change_identifier,
    event_log_type,
    channel,
    description,
    created_at AS ts_created
FROM
    datalake_rental_management_raw.managed_rental_users_log
