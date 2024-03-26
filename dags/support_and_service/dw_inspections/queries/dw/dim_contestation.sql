SELECT
    c.id_contestation AS sk_contestation,
    c.comment,
    c.reason,
    c.ts_updated,
    NOW() AS ts_load,
    c.year,
    c.month,
    c.day
FROM
    datalake_inspections_clean.contestation AS c
WHERE
    c.year = {year}
    AND c.month = {month}
    AND c.day = {day}