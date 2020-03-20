select
    regexp_extract(_id, '\\"(\\w+)\\"', 1) as id,
    regexp_extract(taskid, '\\"(\\w+)\\"', 1) as id_task,
    agentid as id_agent,
    active as is_active,
    assignee,
    autodialerresponse as auto_dialer_response,
    score,
    cast(regexp_extract(snoozeduntil, '(\\d{{4}}-\\d{{2}}-\\d{{2}}\\w{{1}}\\d{{2}}:\\d{{2}}:\\d{{2}})', 1) as timestamp) as snoozed_until,
    tasklink as task_link,
    tasktype as task_type,
    cast(regexp_extract(createddate, '(\\d{{4}}-\\d{{2}}-\\d{{2}}\\w{{1}}\\d{{2}}:\\d{{2}}:\\d{{2}})', 1) as timestamp) as ts_created,
    cast(regexp_extract(updateddate, '(\\d{{4}}-\\d{{2}}-\\d{{2}}\\w{{1}}\\d{{2}}:\\d{{2}}:\\d{{2}})', 1) as timestamp) as ts_updated,
    year,
    month,
    day
from
    datalake_autodialer_raw.taskreferences
where
    year={year} and month={month} and day={day}