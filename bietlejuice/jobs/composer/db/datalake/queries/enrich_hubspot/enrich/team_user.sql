WITH united_users AS (
    SELECT
        id_team::BIGINT,
        EXPLODE(user_ids) AS id_user,
        TRUE AS is_primary
    FROM
        datalake_hubspot_clean.team
    UNION ALL
    SELECT
        id_team::BIGINT,
        EXPLODE(secondary_user_ids) AS id_user,
        FALSE AS is_primary
    FROM
        datalake_hubspot_clean.team
)
SELECT
    id_team,
    id_user::BIGINT,
    is_primary
FROM
    united_users