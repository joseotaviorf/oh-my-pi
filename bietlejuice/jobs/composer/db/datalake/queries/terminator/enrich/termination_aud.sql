SELECT
    id,
    id_contract,
    id_exit_inspection,
    rev,
    rev_type,
    rev_end,
    feedback,
    status,
    source,
    requested_by,
    CASE
        WHEN source = 'CRM' AND requested_by = 'TENANT' AND feedback IS NULL 
            THEN 'UNKNOWN'
        ELSE get_json_object(feedback, '$.reason') 
    END AS reason,
    dt_termination,
    dt_vacancy,
    ts_canceled,
    ts_created,
    ts_updated
FROM
    datalake_terminator_clean.termination_aud