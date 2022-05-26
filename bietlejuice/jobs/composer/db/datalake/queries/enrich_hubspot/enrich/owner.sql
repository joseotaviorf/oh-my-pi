WITH numbered_owner_history AS (
    SELECT *,
        ROW_NUMBER() OVER(PARTITION BY id_owner ORDER BY ts_updated DESC) AS rw
    FROM
        datalake_hubspot.owner_history
)
SELECT
    id_owner,
    id_user,
    email,
    first_name,
    last_name,
    teams,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    numbered_owner_history
WHERE
    rw = 1
    AND NOT is_archived