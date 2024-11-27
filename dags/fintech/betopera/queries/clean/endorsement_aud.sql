SELECT
    id,
    certificate_id AS id_certificate,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    process_info,
    type,
    status,
    created_at_mod AS mod_created_at,
    certificate_id_mod AS mod_id_certificate,
    updated_at_mod AS mod_updated_at,
    status_mod AS mod_status,
    type_mod AS mod_type,
    process_info_mod AS mod_process_info,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.endorsement_aud
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
