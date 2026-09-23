SELECT
    table,
    dag,
    task,
    layer,
    files_location,
    qty_modified_partitions,
    qty_modified_files,
    min_file_size_in_bytes,
    q25_size_in_bytes,
    q50_size_in_bytes,
    q75_size_in_bytes,
    max_file_size_in_bytes,
    avg_file_size_in_bytes,
    qty_smaller_than_1mb,
    qty_bigger_than_1gb,
    total_modified_files_size_in_bytes,
    is_delta,
    criticality,
    sla_deadline_localtime,
    year,
    month,
    day
FROM
    datalake_dag_inventory_raw.table
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}