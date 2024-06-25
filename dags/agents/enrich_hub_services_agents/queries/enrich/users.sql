WITH users AS (
    SELECT
        u.id,
        COALESCE(um.id_user, u.id_external) AS id_external,
        u.name,
        u.email,
        u.phone_number,
        u.ts_created,
        u.ts_updated,
        u.year,
        u.month,
        u.day
    FROM
        datalake_hub_services_clean.users AS u
    LEFT JOIN
        datalake_ebdb_user.user_merge AS um
            ON ARRAY_CONTAINS(um.predecessor_user_list, u.id_external)
    QUALIFY
        u.ts_updated = FIRST(u.ts_updated) OVER (PARTITION BY u.id ORDER BY u.ts_updated DESC)
)
SELECT
    u.id AS id_user,
    u.id_external AS id_main_user,
    ua.id_agent,
    COALESCE(u.name, ua.name) AS name,
    COALESCE(u.email, ua.email) AS email,
    COALESCE(u.phone_number, ua.number) AS phone_number,
    ua.is_active,
    u.ts_created,
    u.ts_updated,
    u.year,
    u.month,
    u.day
FROM
    users AS u
LEFT JOIN
    datalake_ebdb_clean.user AS ua
        ON ua.id = u.id_external