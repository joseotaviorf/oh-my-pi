SELECT
    'user_id',
    username,
    id_address,
    user_agent,
    'status',
    TO_TIMESTAMP(REPLACE(REPLACE(created_date, 'T', ' '), 'Z', ''), 'yyyy-MM-dd HH:mm:ss') AS ts_created
FROM
    datalake_onetrust_raw.audit