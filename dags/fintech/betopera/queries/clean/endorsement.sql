SELECT
    id,
    certificate_id AS id_certificate,
    process_info,
    type,
    status,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.endorsement
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
