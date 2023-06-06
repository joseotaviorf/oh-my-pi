SELECT
    context,
    dag,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.dags_sla_exclusion_list