with tasks_updated as (
    with t_max as (
    SELECT id, max(dt) as max_dt FROM datalake_clean.crm_tasks
    WHERE type in ({task_types})
    GROUP BY 1
    )
    SELECT ct.*
    from datalake_clean.crm_tasks ct
    JOIN t_max m
        on m.id = ct.id AND dt = max_dt
    WHERE type in ({task_types})
),
min_max_id_hosanna as (
SELECT m.codigo, min(id) as min_id, max(id) as max_id
FROM datalake_raw.autodialer_mailing_list m
GROUP BY 1
),
mailing_list_updated_max as (
SELECT m.*
FROM datalake_raw.autodialer_mailing_list m
JOIN min_max_id_hosanna mh on mh.codigo = m.codigo AND mh.max_id = m.id
),
mailing_list_updated_min as (
SELECT m.*
FROM datalake_raw.autodialer_mailing_list m
JOIN min_max_id_hosanna mh on mh.codigo = m.codigo AND mh.min_id = m.id
),
first_call as (
SELECT
    task_id,
    MIN(case when taskreferenceeventorigin = 'WEB_HOOK_BEFORE_NOTIFICATION' then eventdate end) as "ts_first_call",
    MIN(case when taskreferenceeventorigin = 'WEB_HOOK_AFTER_NOTIFICATION' then eventdate end) as "ts_first_connection"
FROM datalake_clean.autodialer_task_reference_inbound_event_histories
WHERE taskreferenceeventorigin in ('WEB_HOOK_BEFORE_NOTIFICATION','WEB_HOOK_AFTER_NOTIFICATION')
GROUP BY 1
)
SELECT
    cast(l.id as integer) as "sk_lead",
    t.id as "sk_task",
    cast(try(date_format(date_parse(r.created_date, '%Y-%m-%d %H:%i:%s.%f'), '%Y%m%d')) as integer) as "sk_imported_to_task_references_date",
    try(date_parse(r.created_date, '%Y-%m-%d %H:%i:%s.%f')) as "ts_imported_to_task_references",
    r.active as "is_active_in_task_references",
    cast(try(date_format(date_parse(m2.is_importacao_datahora, '%Y-%m-%dT%H:%i:%s.%fZ'), '%Y%m%d')) as integer) as "sk_imported_to_mailing_list_date",
    try(date_parse(m2.is_importacao_datahora, '%Y-%m-%dT%H:%i:%s.%fZ')) as "ts_imported_to_mailing_list",
    m1.active = 'Y' as "is_active_in_mailing_list",
    cast(try(date_format(date_parse(events.ts_first_call, '%Y-%m-%d %H:%i:%s.%f'), '%Y%m%d')) as integer) as sk_first_call_date,
    try(date_parse(events.ts_first_call, '%Y-%m-%d %H:%i:%s.%f')) as ts_first_call,
    cast(try(date_format(date_parse(events.ts_first_connection, '%Y-%m-%d %H:%i:%s.%f'), '%Y%m%d')) as integer) as sk_first_connection_date,
    try(date_parse(events.ts_first_connection, '%Y-%m-%d %H:%i:%s.%f')) as ts_first_connection,
    coalesce((mlc.active = 'Y'), false) as is_mailing_active,
    coalesce((mlc.estado = 'P'), false) as is_mailing_paused,
    now() as ts_load
FROM datalake_raw.ebdb_lead l
JOIN tasks_updated t on t.id_origin = l.id
LEFT JOIN datalake_clean.autodialer_task_references r on r.task_id = t.id
LEFT JOIN mailing_list_updated_max m1 on m1.codigo = r.task_id
LEFT JOIN mailing_list_updated_min m2 on m2.codigo = r.task_id
LEFT JOIN first_call events on events.task_id = t.id
LEFT JOIN datalake_raw.autodialer_mailing_list_conf mlc on mlc.id = m1.easy_disc_mailing_conf_id
WHERE cast(coalesce(NULLIF(l.forrent, ''), '1') as boolean)