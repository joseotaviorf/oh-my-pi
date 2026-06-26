SELECT
    id,
    managed_rental_user_uuid,
    managed_rental_id AS id_managed_rental,
    person_uuid,
    version,
    status,
    role_related_as,
    profiles,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.managed_rental_users
