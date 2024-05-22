WITH external_user AS (
    SELECT 
        u.id_user,
        u.id_agent,
        u.name,
        u.email,
        u.number AS phone_number,
        COALESCE(us.is_active, FALSE) AS is_active
    FROM
        datalake_ebdb_clean.user_aud AS u 
        -- the audit table keeps users merged, and therefore has greater compatibility with Hub Services data
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON ure.id = u.rev
    LEFT JOIN
        datalake_ebdb_clean.user AS us
            ON us.id = u.id_user
    WHERE
        ure.ts_revision <= MAKE_DATE({year}, {month}, {day})
    QUALIFY
        ure.ts_revision = MAX(ure.ts_revision) OVER(PARTITION BY u.id_user)
)
SELECT
    u.id AS id_user,
    u.id_external AS id_main_user,
    ua.id_agent,
    COALESCE(u.name, ua.name) AS name,
    COALESCE(u.email, ua.email) AS email,
    COALESCE(u.phone_number, ua.phone_number) AS phone_number,
    ua.is_active,
    u.ts_created,
    u.ts_updated,
    u.year,
    u.month,
    u.day
FROM
    datalake_hub_services_clean.users AS u
LEFT JOIN
    external_user AS ua
        ON ua.id_user = u.id_external
WHERE
    u.year = {year}
    AND u.month = {month}
    AND u.day = {day}
