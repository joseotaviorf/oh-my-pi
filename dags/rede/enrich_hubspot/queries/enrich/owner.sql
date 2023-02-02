WITH most_recent_id_user AS (
    SELECT
        id_owner,
        id_user
    FROM
        datalake_hubspot.owner_history
    WHERE
        id_user IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_owner ORDER BY ts_updated DESC) = 1
        AND ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY ts_updated DESC) = 1
)
SELECT
    oh.id_owner,
    COALESCE(oh.id_user, mriu.id_user) AS id_user,
    email,
    first_name,
    last_name,
    teams,
    is_archived,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    datalake_hubspot.owner_history AS oh
LEFT JOIN
    most_recent_id_user AS mriu
        ON oh.id_owner = mriu.id_owner
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY oh.id_owner ORDER BY ts_updated DESC) = 1