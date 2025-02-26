SELECT
    dag_id,
    fileloc,
    fileloc_hash,
    CAST(data AS VARCHAR) AS data,
    last_updated,
    dag_hash,
    processor_subdir
FROM
    serialized_dag
WHERE
    last_updated >= DATE('{load_start_date}')
    AND last_updated <= DATE('{load_end_date}')
