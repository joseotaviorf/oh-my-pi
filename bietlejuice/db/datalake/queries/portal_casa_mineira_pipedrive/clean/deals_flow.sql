SELECT
    id as id_deal_flow,
    id_deal,
    old_stage,
    new_stage,
    field_key, 
    log_time as ts_log,
    year,
    month,
    day
FROM 
    datalake_portal_casa_mineira_pipedrive_raw.deals_flow
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}