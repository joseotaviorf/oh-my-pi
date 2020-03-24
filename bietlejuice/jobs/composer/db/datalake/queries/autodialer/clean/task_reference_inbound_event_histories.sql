with exploded_events as (
  select
    regexp_extract(_id, '\\"(\\w+)\\"', 1) as id,
    regexp_extract(taskid, '\\"(\\w+)\\"', 1) as id_task,
    explode_outer(from_json(inboundevents, 'array<string>')) as events_json,
    cast(regexp_extract(createdat, '(\\d{{4}}-\\d{{2}}-\\d{{2}}\\w{{1}}\\d{{2}}:\\d{{2}}:\\d{{2}})', 1) as timestamp) as ts_created,
    cast(regexp_extract(updatedat, '(\\d{{4}}-\\d{{2}}-\\d{{2}}\\w{{1}}\\d{{2}}:\\d{{2}}:\\d{{2}})', 1) as timestamp) as ts_updated,
    year,
    month,
    day
  from datalake_autodialer_raw.taskreferenceinboundeventhistories
)
select
  id,
  id_task,
  get_json_object(events_json, '$.taskReferenceEventOrigin') as task_reference_event_origin,
  cast(date_format(regexp_extract(get_json_object(events_json, '$.eventDate'), '(\\d{{4}}-\\d{{2}}-\\d{{2}}\\w{{1}}\\d{{2}}:\\d{{2}}:\\d{{2}})', 1), 'YYYY-MM-dd HH:mm:ss') as timestamp) as event_date,
  cast(date_format(regexp_extract(get_json_object(events_json, '$.snoozed'), '(\\d{{4}}-\\d{{2}}-\\d{{2}}\\w{{1}}\\d{{2}}:\\d{{2}}:\\d{{2}})', 1), 'YYYY-MM-dd HH:mm:ss') as timestamp) as snoozed,
  ts_created,
  ts_updated,
  year,
  month,
  day
from
  exploded_events
where
    year={year} and month={month} and day={day}