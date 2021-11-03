SELECT
    id as id_stage,
    pipeline_id as id_pipeline,
    name as stage_name,
    pipeline_name,
    order_nr as order_number,
    active_flag as is_active_flag,
    add_time as ts_added,
    update_time as ts_updated,
    year,
    month,
    day
FROM 
    datalake_portal_casa_mineira_pipedrive_raw.stages
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}