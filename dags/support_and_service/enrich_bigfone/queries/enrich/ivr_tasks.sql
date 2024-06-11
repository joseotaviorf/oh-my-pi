SELECT
    id_task,
    id_call,
    from_phone_number,
    to_phone_number,
    STR_TO_MAP(
        REGEXP_REPLACE(REPLACE(ivr_steps, '"', ''), '^\\{|\\}\\}$', ""),
        '\\},',
        ':\\{'
    ) AS ivr_steps,
    ts_created
FROM
    datalake_bigfone_clean.event
WHERE
    workflow_name = 'IVR Events'
    AND ivr_steps IS NOT NULL
    AND MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_task ORDER BY ts_created) = 1
