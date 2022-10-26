SELECT
    user_group_id,
    'name',
    'description',
    created_by,
    last_modified_by,
    TO_TIMESTAMP(REPLACE(created_date, 'T', ' '), 'yyyy-MM-dd HH:mm:ss.SSS') AS ts_created,
    TO_TIMESTAMP(REPLACE(last_modified_date, 'T', ' '), 'yyyy-MM-dd HH:mm:ss.SSS') AS ts_last_modified
FROM
    datalake_onetrust_raw.user_groups