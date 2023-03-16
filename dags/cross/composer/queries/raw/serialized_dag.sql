SELECT
    dag_id,
    fileloc,
    fileloc_hash,
    data,
    last_updated,
    dag_hash
FROM
    serialized_dag
WHERE
    DATE(last_updated) = DATE('{start_date}')
