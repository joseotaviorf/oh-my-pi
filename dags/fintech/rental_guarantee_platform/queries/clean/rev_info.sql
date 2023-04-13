SELECT
    rev,
    TO_TIMESTAMP(revtstmp/1000) AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.revinfo
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
