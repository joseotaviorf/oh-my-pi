SELECT
    dag_id AS id_dag,
    data AS json_data,
    fileloc,
    fileloc_hash,
    dag_hash,
    processor_subdir,
    last_updated::TIMESTAMP AS ts_last_updated,
    year,
    month,
    day
FROM
    datalake_astro_raw.serialized_dag
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
