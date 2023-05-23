SELECT
    id,
    legacy_id   AS id_legacy,
    userinsert  AS id_user_insert,
    userupdate  AS id_user_update,
    type        AS id_type,
    name        AS plan_name,
    CAST(pricing AS NUMERIC(7,4))       AS pricing,
    coverage,
    damage,
    CAST(commission AS NUMERIC(7,4))    AS commission,
    active      AS is_active,
    dateinsert  AS ts_inserted,
    dateupdate  AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.plan

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY dateupdate DESC) = 1
