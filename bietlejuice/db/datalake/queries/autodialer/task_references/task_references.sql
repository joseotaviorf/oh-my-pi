SELECT
    _id as id,
    _class as class,
    active as active,
    agentid as agent_id,
    assignee,
    autodialerresponse as auto_dialer_response,
    createddate as created_date,
    score,
    snoozeduntil as snoozed_until,
    taskid as task_id,
    tasklink as task_link,
    tasktype as task_type,
    updateddate as updated_date,
    dialstatus
FROM
    datalake_raw.autodialer_task_references
WHERE createddate IS NOT NULL
