SELECT
    id,
    relationships[0].user.data.id AS id_user,
    attributes.title,
    attributes.url AS url_certificate,
    attributes.certificate_number AS certificate_number,
    attributes.issued_by AS issuer,
    TO_TIMESTAMP(attributes.started_at) AS ts_started,
    TO_TIMESTAMP(attributes.completed_at) AS ts_completed,
    NOW() AS ts_load
FROM
    datalake_degreed_raw.certificates
WHERE
    DATE(attributes.started_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
