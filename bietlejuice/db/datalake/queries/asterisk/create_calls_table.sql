with asterisk_data as (
    select * from datalake_raw.asterisk_logs_full
    where dt='2019-03-19'
),
ids_calls as (
    SELECT
        regexp_extract(content,'VERBOSE\[[0-9]+\]\[C-(\w+)\]', 1) as id_call
    FROM asterisk_data
    WHERE content like '%[C-000063b1]%'
    GROUP by
     1
),
events_ura as (
  SELECT
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/3001-(\w+)", "(NOW|QUEUEJOINTIME)=(\d+)"', 2) as id_call,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/3001-(\w+)", "(NOW|QUEUEJOINTIME)=(\d+)"', 3) as id_ura,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/3001-(\w+)", "NOW=(\d+)"', 1) as ts_start_ura,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/3001-(\w+)", "QUEUEJOINTIME=(\d+)"', 1) as ts_end_ura
  FROM asterisk_data
  WHERE content like '%[C-000063b1]%'
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
  WHERE content like '%[C-000063b1]%'
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

URA AS (
    SELECT 
       id_call,
       id_ura,
       max(ts_start_ura) as ts_start_ura,
       max(ts_end_ura) as ts_end_ura
    FROM events_ura
    GROUP BY 1,2
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
ORDER BY q.ts_start_queue