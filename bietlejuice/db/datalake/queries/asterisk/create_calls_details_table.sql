with asterisk_data as (
    select dt,content from datalake_raw.asterisk_logs_full
    where date(from_iso8601_timestamp(dt)) = date('{partition_date}')
),
ids_calls as (
    select
        regexp_extract(content,'VERBOSE\[[0-9]+\]\[C-(\w+)\]', 1) as id_call
    from asterisk_data
    -- where content like '%[C-XXXXXXXX]%' (filter per call)
    group by 1
),
events_ura as (
  select
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)"', 2) as id_call,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)"', 3) as id_ura,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "NOW=(\d+)"', 1) as ts_start_ura,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "QUEUEJOINTIME=(\d+)"', 1) as ts_end_ura
  from asterisk_data
  group by 1,2,3,4
),
events_typed as (
  select 
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on SIP/\d+-(\w+)', 2) as id_call,  
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on SIP/\d+-(\w+)', 4) as id_ura,          
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on SIP/\d+-(\w+)', 3) as typed_answer,
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on SIP/\d+-(\w+)', 1) as ts_start_typed_answer
  from asterisk_data
  group by 1,2,3,4
),
events_audio_message as (
  select
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<SIP/\d+-(\w+)> Playing .custom/(\w+).gsm.+', 2) as id_call,
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<SIP/\d+-(\w+)> Playing .custom/(\w+).gsm.+', 3) as id_ura,
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<SIP/\d+-(\w+)> Playing .custom/(\w+).gsm.+', 4) as audio_message,
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<SIP/\d+-(\w+)> Playing .custom/(\w+).gsm.+', 1) as ts_start_audio_message
  from asterisk_data
  group by 1,2,3,4
),
events_queue as (
  select
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QAGENT=(\d+)"', 2) as id_call,
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QAGENT=(\d+)"', 3) as id_caller,  
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QAGENT=(\d+)"', 4) as id_queue,
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QAGENT=(\d+)"', 1) as ts_start_queue
  from asterisk_data
  group by 1,2,3,4     
),
events_attendance as (
	select 
	    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',2) as id_call,
	    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',1) as ts_start_attendance,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',3) as id_caller,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',4) as id_attendance,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',5) as id_queue	    
    from asterisk_data   
    group by 1,2,3,4,5
),
events_queue_join_attendance as (
    select
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QUEUEJOINTIME=(\d+)"', 1) as ts_queue_join_time,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QUEUEJOINTIME=(\d+)"', 2) as id_call, 
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QUEUEJOINTIME=(\d+)"', 3) as id_caller,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QUEUEJOINTIME=(\d+)"', 4) as id_queue
    from asterisk_data
    group by 1,2,3,4
),
events_hangup as (
    select
       regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("PJSIP/(\d+)-(\w+)".+HANGUP CAUSE: (\d+)"\) in new stack', 1) as ts_hangup,
       regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("PJSIP/(\d+)-(\w+)".+HANGUP CAUSE: (\d+)"\) in new stack', 2) as id_call,
       regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("PJSIP/(\d+)-(\w+)".+HANGUP CAUSE: (\d+)"\) in new stack', 3) as id_caller,
       regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("PJSIP/(\d+)-(\w+)".+HANGUP CAUSE: (\d+)"\) in new stack', 4) as id_attendance,
       regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("PJSIP/(\d+)-(\w+)".+HANGUP CAUSE: (\d+)"\) in new stack', 5) as cod_hangup_cause
    from asterisk_data
    group by 1,2,3,4,5
),
events_source as (
    select
        regexp_extract(content, 'VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\(".+", "(__CRM_SOURCE|CALLERID\(number\))=(\d+)"\) in new stack', 1) as id_call,
        regexp_extract(content, 'VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\(".+", "(__CRM_SOURCE|CALLERID\(number\))=(\d+)"\) in new stack', 3) as call_source_number 
    from asterisk_data
    group by 1,2
),
events_destination as (
    select
        regexp_extract(content, 'VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\(".+", "__CRM_DESTINATION=(\d+)"\) in new stack', 1) as id_call,
        regexp_extract(content, 'VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\(".+", "__CRM_DESTINATION=(\d+)"\) in new stack', 2) as call_destination_number 
    from asterisk_data
    group by 1,2    
),
URA_HELP AS (
    select 
      m.id_call,
      m.id_ura,
      m.ts_start_audio_message,
      min(cast(ty.ts_start_typed_answer as timestamp)) as ts_min_start_typed_answer
    from  events_audio_message m
    left join events_typed ty on (ty.id_call = m.id_call and ty.id_ura = m.id_ura)  
    where 
        m.audio_message LIKE 'URA_HELP_NEW%' 
        and (ty.typed_answer like '2' OR ty.typed_answer like '3')
        and cast(m.ts_start_audio_message as timestamp) <= cast(ty.ts_start_typed_answer as timestamp)
    group by 1,2,3
),
URA AS (
    select 
       e.id_call,
       e.id_ura,
       case 
        when ty.typed_answer='2' then 'True'
        when ty.typed_answer='3' then 'False'
        else NULL
       end as is_ura_help_solved,
       max(e.ts_start_ura) as ts_start_ura,
       max(e.ts_end_ura) as ts_end_ura
    FROM events_ura e
    left join URA_HELP uh 
    on (uh.id_call = e.id_call and uh.id_ura = e.id_ura)
    left join events_typed ty 
    on (ty.id_call = uh.id_call and ty.id_ura = uh.id_ura and cast(ty.ts_start_typed_answer as timestamp)=uh.ts_min_start_typed_answer)  
    group by 1,2,3
),
QUEUES as (
	select 
		q.id_call,
		q.id_queue,
		q.id_caller,
        a.id_attendance,
		q.ts_start_queue,
        h.ts_hangup as ts_end_attendance,
        coalesce(a.ts_start_attendance,j.ts_queue_join_time) as ts_end_queue
    from events_queue q
    left join events_attendance a
    on q.id_call = a.id_call and q.id_caller = a.id_caller and q.id_queue = a.id_queue
    left join events_queue_join_attendance j
    on j.id_call = a.id_call and j.id_caller = a.id_caller and j.id_queue = a.id_queue
    left join events_hangup h
    on h.id_call = a.id_call and h.id_caller = a.id_caller and h.id_attendance = a.id_attendance
    group by
     	1,2,3,4,5,6,7
)
SELECT
    id_c.id_call,
    s.call_source_number,
    d.call_destination_number,
    u.id_ura,
    u.ts_start_ura,
    u.ts_end_ura,
    u.is_ura_help_solved,
    q.id_queue,
    q.id_caller, -- RAMAL
    q.ts_start_queue,
    q.ts_end_queue,
    a.id_attendance,
    a.ts_start_attendance,
    q.ts_end_attendance,
    cast(date_diff('second', cast(u.ts_start_ura as timestamp), cast(u.ts_end_ura as timestamp)) as varchar) as sec_time_duration_ura,
    cast(date_diff('second', cast(q.ts_start_queue as timestamp), cast(q.ts_end_queue as timestamp)) as varchar) as sec_time_duration_queue,
    cast(date_diff('second', cast(a.ts_start_attendance as timestamp), cast(q.ts_end_attendance as timestamp)) as varchar) as sec_time_duration_attendance
FROM
    ids_calls id_c
left join QUEUES q 
on id_c.id_call=q.id_call
left join URA u 
on id_c.id_call=u.id_call
left join events_source s 
on id_c.id_call=s.id_call
left join events_destination d 
on id_c.id_call=d.id_call
left join events_attendance a 
on id_c.id_call=a.id_call and q.id_caller = a.id_caller
where id_c.id_call is not null;