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
task_reference_inbound_event_histories as (
  with task_reference_inbound_event_histories_last_update as (
    select
        id_task,
        max(ts_updated) as max_ts_updated
    from datalake_autodialer_clean_prod.task_reference_inbound_event_histories
    group by 1
  )
  select
    id_task,
    event_date,
    task_reference_event_origin
  from datalake_autodialer_clean_prod.task_reference_inbound_event_histories t
  join task_reference_inbound_event_histories_last_update trlu
    on trlu.id_task = t.id_task and trlu.max_ts_updated = t.ts_updated
),
first_call as (
    SELECT
        id_task,
        MIN(case when task_reference_event_origin = 'WEB_HOOK_BEFORE_NOTIFICATION' then event_date end) as "ts_first_call",
        MIN(case when task_reference_event_origin = 'WEB_HOOK_AFTER_NOTIFICATION' then event_date end) as "ts_first_connection"
    FROM task_reference_inbound_event_histories
    WHERE task_reference_event_origin in ('WEB_HOOK_BEFORE_NOTIFICATION','WEB_HOOK_AFTER_NOTIFICATION')
    GROUP BY 1
),
task_references as (
  with task_references_last_update as (
    select
        id_task,
        max(ts_updated) as max_ts_updated
    from datalake_autodialer_clean_prod.task_references
    group by 1
  )
  select
      id_task,
      is_active,
      ts_created
  from datalake_autodialer_clean_prod.task_references r
  join task_references_last_update trlu
    on trlu.id_task = r.id_task and trlu.max_ts_updated = r.ts_updated
)
SELECT
    cast(l.id as integer) as "sk_lead",
    t.id as "sk_task",
    cast(date_format(r.ts_created, '%Y%m%d') as integer) as "sk_imported_to_task_references_date",
    r.ts_created as "ts_imported_to_task_references",
    r.is_active as "is_active_in_task_references",
    cast(try(date_format(date_parse(m2.is_importacao_datahora, '%Y-%m-%dT%H:%i:%s.%fZ'), '%Y%m%d')) as integer) as "sk_imported_to_mailing_list_date",
    try(date_parse(m2.is_importacao_datahora, '%Y-%m-%dT%H:%i:%s.%fZ')) as "ts_imported_to_mailing_list",
    m1.active = 'Y' as "is_active_in_mailing_list",
    cast(date_format(events.ts_first_call, '%Y%m%d') as integer) as sk_first_call_date,
    events.ts_first_call,
    cast(date_format(events.ts_first_connection, '%Y%m%d') as integer) as sk_first_connection_date,
    events.ts_first_connection,
    coalesce((mlc.active = 'Y'), false) as is_mailing_active,
    coalesce((mlc.estado = 'P'), false) as is_mailing_paused,
    now() as ts_load
FROM datalake_ebdb_clean_prod.lead l
JOIN tasks_updated t on t.id_origin = cast(l.id as varchar)
LEFT JOIN task_references r on r.id_task = t.id
LEFT JOIN mailing_list_updated_max m1 on m1.codigo = r.id_task
LEFT JOIN mailing_list_updated_min m2 on m2.codigo = r.id_task
LEFT JOIN first_call events on events.id_task = t.id
LEFT JOIN datalake_raw.autodialer_mailing_list_conf mlc on mlc.id = m1.easy_disc_mailing_conf_id    -- Not renaming because we're using select * to mailing_list_updated_max because it's large
WHERE coalesce(has_processed, true) != false