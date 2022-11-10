SELECT
    table,
    dag,
    task,
    layer,
    files_location,
    qty_smaller_than_1mb,
    qty_bigger_than_1gb,
    qty_total_files,
    year,
    month,
    day
FROM
    datalake_dag_inventory_raw.table
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}