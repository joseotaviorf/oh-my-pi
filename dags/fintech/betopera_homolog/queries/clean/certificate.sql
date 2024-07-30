SELECT
    id,
    insurance_id AS id_insurance,
    certificate_request_id AS id_certificate_request,
    version,
    status,
    response_payload,
    file_url,
    DATE(start_date) AS dt_start,
    DATE(end_date) AS dt_end,
    DATE(cancel_date) AS dt_cancel,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_homolog_raw.certificate
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
