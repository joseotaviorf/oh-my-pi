SELECT
    id,
    managed_rental_users_id AS id_managed_rental_users,
    email,
    phone,
    version,
    last_sent_at AS ts_last_sent,
    accepted_at AS ts_accepted,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.managed_rental_users_invitation
