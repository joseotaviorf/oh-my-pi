SELECT
    id,
    dttm,
    dag_id,
    task_id,
    event,
    execution_date,
    owner,
    extra,
    YEAR(dttm) AS year,
    MONTH(dttm) AS month,
    DAY(dttm) AS day
FROM
    log
WHERE
    DATE(dttm) >= DATE('2022-01-01') -- DATE('{start_date}')
    AND dag_id REGEXP 'bietlejuice'