SELECT
    id,
    personuuid AS uuid_person,
    email,
    status,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_guarantee_platform_raw.user_account
