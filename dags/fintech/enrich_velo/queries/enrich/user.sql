WITH person AS (
    SELECT *
    FROM
        datalake_person_clean.person AS p
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY p.id ORDER BY p.ts_updated DESC) = 1
)
SELECT DISTINCT
    ua.id AS id_user,
    ua.uuid_person AS uuid_user,
    p.person_name AS name,
    ua.email,
    pa.profile_name AS user_role,
    ua.id <= 5000000 AS is_legacy,
    ua.ts_created
FROM
    datalake_rental_guarantee_platform_clean.user_account AS ua
LEFT JOIN
    datalake_rental_guarantee_platform_clean.company_user_account AS cua
    ON ua.id = cua.id_user_account
LEFT JOIN
    datalake_rental_guarantee_platform_clean.profile_account AS pa
    ON cua.id_profile_account = pa.id
LEFT JOIN
    person AS p
    ON ua.uuid_person = p.uuid_person
