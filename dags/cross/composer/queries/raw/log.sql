SELECT
    id,
    dttm,
    dag_id,
    task_id,
    event,
    execution_date,
    owner,
    extra
FROM
    log
WHERE
    DATE(dttm) = DATE('{start_date}')
    AND dag_id REGEXP 'bietlejuice'