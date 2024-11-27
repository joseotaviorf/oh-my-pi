SELECT
    id,
    insurance_id AS id_insurance,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    version,
    payload,
    status,
    insurance_id_mod AS mod_id_insurance,
    payload_mod AS mod_payload,
    status_mod AS mod_status,
    synced_at_mod AS mod_synced_at,
    TIMESTAMP(synced_at) AS ts_synced,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.certificate_request_aud
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
