SELECT
    GET_JSON_OBJECT(REPLACE(_id, '$', ''), '$.oid') AS id,
    GET_JSON_OBJECT(REPLACE(taskId, '$', ''), '$.oid') AS id_task,
    agentid AS id_agent,
    active AS is_active,
    assignee,
    autodialerresponse AS auto_dialer_response,
    score,
    CAST(GET_JSON_OBJECT(REPLACE(snoozeduntil, '$',  ''), '$.date') AS TIMESTAMP) AS snoozed_until,
    tasklink AS task_link,
    tasktype AS task_type,
    CAST(GET_JSON_OBJECT(REPLACE(createddate, '$',  ''), '$.date') AS TIMESTAMP) AS ts_created,
    CAST(GET_JSON_OBJECT(REPLACE(updateddate, '$',  ''), '$.date') AS TIMESTAMP) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_autodialer_raw.taskreferences
WHERE
    year={year} 
    AND month={month} 
    AND day={day}