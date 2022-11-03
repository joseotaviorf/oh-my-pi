SELECT
    id_owner,
    id_user,
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
    datalake_hubspot.owner_history
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_owner ORDER BY ts_updated DESC) = 1