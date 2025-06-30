SELECT
    id,
    uri,
    is_orphaned,
    created_at::TIMESTAMP AS ts_created,
    updated_at::TIMESTAMP AS ts_updated,
    year,
    month,
    day
FROM
    datalake_astro_raw.dataset
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
