with asterisk_data as (
    select * from datalake_raw.asterisk_logs_full
    where dt='2019-03-19'
),
ids_calls as (
    SELECT
        regexp_extract(content,'VERBOSE\[[0-9]+\]\[C-(\w+)\]', 1) as id_call
    FROM asterisk_data
   -- WHERE content like '%[C-000063b1]%'
    GROUP by
     1
),
events_ura as (
  SELECT
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)"', 2) as id_call,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)"', 3) as id_ura,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "NOW=(\d+)"', 1) as ts_start_ura,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "QUEUEJOINTIME=(\d+)"', 1) as ts_end_ura
  FROM asterisk_data
  GROUP BY 1,2,3,4
),

-- [2019-03-18 08:47:16] VERBOSE[27307][C-000063b1] file.c: <SIP/3001-0000510b> Playing 'custom/URA_HELP_NEW.gsm' (language 'en')
-- [2019-03-18 08:47:28] DTMF[27307][C-000063b1] channel.c: DTMF begin '3' received on SIP/3001-0000510b
events_typed as (
  SELECT 
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on SIP/\d+-(\w+)', 2) as id_call,  
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on SIP/\d+-(\w+)', 4) as id_ura,          
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on SIP/\d+-(\w+)', 3) as typed_answer,
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on SIP/\d+-(\w+)', 1) as ts_start_typed_answer
  FROM asterisk_data
  GROUP BY 1,2,3,4
),

events_audio_message as (
  SELECT
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<SIP/\d+-(\w+)> Playing .custom/(\w+).gsm.+', 2) as id_call,
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<SIP/\d+-(\w+)> Playing .custom/(\w+).gsm.+', 3) as id_ura,
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<SIP/\d+-(\w+)> Playing .custom/(\w+).gsm.+', 4) as audio_message,
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<SIP/\d+-(\w+)> Playing .custom/(\w+).gsm.+', 1) as ts_start_audio_message
  FROM asterisk_data
  GROUP BY 1,2,3,4
),

events_queue as (
  SELECT
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QAGENT=(\d+)"', 2) as id_call,
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QAGENT=(\d+)"', 3) as id_caller,  
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QAGENT=(\d+)"', 4) as id_queue,
    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QAGENT=(\d+)"', 1) as ts_start_queue
    --regexp_extract(content,'VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "NOW=(\d+)"', 4) as ts_start_queue,
  FROM asterisk_data
  GROUP BY 1,2,3,4     
),
-- [2019-03-18 08:47:32] VERBOSE[29930][C-000063b1] app_dial.c: PJSIP/8667-00007b7d answered Local/8667@from-queue-00003d78;2
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
    SELECT
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QUEUEJOINTIME=(\d+)"', 1) as ts_queue_join_time,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QUEUEJOINTIME=(\d+)"', 2) as id_call, 
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QUEUEJOINTIME=(\d+)"', 3) as id_caller,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QUEUEJOINTIME=(\d+)"', 4) as id_queue
    FROM asterisk_data
    group by 1,2,3,4
),

--[2019-03-18 08:48:53] VERBOSE[30040][C-000063b1] pbx.c: Executing [s@crm-hangup:2] NoOp("PJSIP/8667-00007b7d", "HANGUP CAUSE: 16") in new stack
events_hangup as (
    SELECT
       regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("PJSIP/(\d+)-(\w+)".+HANGUP CAUSE: (\d+)"\) in new stack', 1) as ts_hangup,
       regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("PJSIP/(\d+)-(\w+)".+HANGUP CAUSE: (\d+)"\) in new stack', 2) as id_call,
       regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("PJSIP/(\d+)-(\w+)".+HANGUP CAUSE: (\d+)"\) in new stack', 3) as id_caller,
       regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("PJSIP/(\d+)-(\w+)".+HANGUP CAUSE: (\d+)"\) in new stack', 4) as id_attendance,
       regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("PJSIP/(\d+)-(\w+)".+HANGUP CAUSE: (\d+)"\) in new stack', 5) as cod_hangup_cause
    FROM asterisk_data
    group by 1,2,3,4,5
),

URA_HELP AS (
    SELECT 
      m.id_call,
      m.id_ura,
      m.ts_start_audio_message,
      min(cast(ty.ts_start_typed_answer as timestamp)) as ts_min_start_typed_answer
    FROM  events_audio_message m
    LEFT JOIN events_typed ty ON (ty.id_call = m.id_call and ty.id_ura = m.id_ura)  
    WHERE 
        m.audio_message LIKE 'URA_HELP_NEW%' 
        AND (ty.typed_answer like '2' OR ty.typed_answer like '3')
        AND cast(m.ts_start_audio_message as timestamp) <= cast(ty.ts_start_typed_answer as timestamp)
    GROUP BY 1,2,3
),

URA AS (
    SELECT 
       e.id_call,
       e.id_ura,
       CASE 
        WHEN ty.typed_answer='2' THEN 'True'
        WHEN ty.typed_answer='3' THEN 'False'
       END is_URA_HELP_solved,
       max(e.ts_start_ura) as ts_start_ura,
       max(e.ts_end_ura) as ts_end_ura
    FROM events_ura e
    LEFT JOIN URA_HELP uh ON (uh.id_call = e.id_call and uh.id_ura = e.id_ura)
    LEFT JOIN events_typed ty ON (ty.id_call = uh.id_call and ty.id_ura = uh.id_ura and cast(ty.ts_start_typed_answer as timestamp)=uh.ts_min_start_typed_answer)  
    GROUP BY 1,2,3
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
    from
       events_queue q
    LEFT JOIN 
       events_attendance a
    ON 
       q.id_call = a.id_call and q.id_caller = a.id_caller and q.id_queue = a.id_queue
    LEFT JOIN
       events_queue_join_attendance j
    ON
       j.id_call = a.id_call and j.id_caller = a.id_caller and j.id_queue = a.id_queue
    LEFT JOIN
       events_hangup h
    ON
       h.id_call = a.id_call and h.id_caller = a.id_caller and h.id_attendance = a.id_attendance
    group by
     	1,2,3,4,5,6,7
)

SELECT
    id_c.id_call,
    u.id_ura,
    u.ts_start_ura,
    u.ts_end_ura,
    cast(u.is_URA_HELP_solved as boolean) as is_URA_HELP_solved,
    q.id_queue,
    q.id_caller,
    q.ts_start_queue,
    q.ts_end_queue,
    --q.ts_end_queue,
    a.id_attendance,
    a.ts_start_attendance,
    q.ts_end_attendance,
    --q.ts_queue_join_time,
    date_diff('second', cast(u.ts_start_ura as timestamp), cast(u.ts_end_ura as timestamp)) as seconds_time_ura,
    date_diff('second', cast(q.ts_start_queue as timestamp), cast(q.ts_end_queue as timestamp)) as seconds_time_queue,
    date_diff('second', cast(a.ts_start_attendance as timestamp), cast(q.ts_end_attendance as timestamp)) as seconds_time_attendance
FROM
    ids_calls id_c
LEFT JOIN QUEUES q ON id_c.id_call=q.id_call
LEFT JOIN URA u ON id_c.id_call=u.id_call
LEFT JOIN events_attendance a ON id_c.id_call=a.id_call and q.id_caller = a.id_caller -- and q.id_queue = a.id_queue
WHERE id_c.id_call IS NOT NULL and q.ts_end_queue IS NOT NULL --and q.ts_start_queue IS NOT NULL
ORDER BY id_c.id_call