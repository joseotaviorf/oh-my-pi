with events_filter as (
    select * from datalake_bigfone_raw.events
    where provider='teravoz' and year={year} and month={month} and day={day}
),
-- we need to do this filter because there is a Teravoz bug that generates service.command 
-- or/and recording.available events with wrong call id (Teravoz internal control call id).
lonely_events as (
    select 
        count(get_json_object(metadata, '$.call_id')) as count_call_id, 
        get_json_object(metadata, '$.call_id') as call_id 
    from events_filter
    where
      event='service.command' or event='recording.available'
    group by 2
    -- Teravoz can generate 2 events with the same wrong call_id (recording and service) 
    having count_call_id <= 2
)
select 
    bigint(events.id) as id,
    events.event as event,
    get_json_object(events.metadata, '$.call_id') as id_call,
    events.metadata as metadata,
    to_timestamp(events.event_timestamp, 'yyyy-MM-dd HH:mm:ss') as ts_created,
    to_timestamp(from_utc_timestamp(events.event_timestamp, 'Brazil/East'), 'yyyy-MM-dd HH:mm:ss') as ts_created_local,
    to_timestamp(events.received_timestamp, 'yyyy-MM-dd HH:mm:ss') as ts_received,
    to_timestamp(from_utc_timestamp(events.received_timestamp, 'Brazil/East'), 'yyyy-MM-dd HH:mm:ss') as ts_received_local,
    events.year as year,
    events.month as month,
    events.day as day  
from events_filter events
left join lonely_events lonely
on lonely.call_id=get_json_object(events.metadata, '$.call_id')
where 
    lonely.call_id is null