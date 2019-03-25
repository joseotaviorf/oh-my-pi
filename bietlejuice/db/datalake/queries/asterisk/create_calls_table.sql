with asterisk_data as (
    select * from datalake_raw.asterisk_logs_full
    where dt='2019-03-19'
),
ids_calls as (
    SELECT
        regexp_extract(content,'VERBOSE\[[0-9]+\]\[C-(\w+)\]', 1) as id_call
    FROM asterisk_data
    WHERE content like '%[C-00007e6a]%'
    GROUP by
     1
),
events_ura as (
  SELECT
        regexp_extract(content,'VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/3001-(\w+)", "(NOW|QUEUEJOINTIME)=(\d+)"', 1) as id_call,
        regexp_extract(content,'VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/3001-(\w+)", "(NOW|QUEUEJOINTIME)=(\d+)"', 2) as id_ura,
        regexp_extract(content,'VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/3001-(\w+)", "(NOW|QUEUEJOINTIME)=(\d+)"', 4) as ts_start_ura,
        regexp_extract(content,'VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/3001-(\w+)", "(NOW|QUEUEJOINTIME)=(\d+)"', 4) as ts_end_ura
  FROM asterisk_data
  WHERE content like '%[C-00007e6a]%'
  GROUP BY 1,2,3,4
),

events_queue as (
  SELECT
    regexp_extract(content,'VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d"', 1) as id_call,
    regexp_extract(content,'VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d"', 2) as id_caller,  
    regexp_extract(content,'VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d"', 3) as id_queue,
    regexp_extract(content,'VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "NOW=(\d+)"', 4) as ts_start_queue,
    regexp_extract(content,'VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/(\d+)@from-queue-(\w+);\d", "QUEUEJOINTIME=(\d+)"', 4) as ts_end_queue
  FROM asterisk_data
  WHERE content like '%[C-00007e6a]%'
  GROUP BY 1,2,3,4,5     
),
-- [2019-03-18 08:47:32] VERBOSE[29930][C-000063b1] app_dial.c: PJSIP/8667-00007b7d answered Local/8667@from-queue-00003d78;2
events_attendance as (
	select 
	    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-.+ answered Local/\d+@from-queue-(\w+);\d',2) as id_call,
	    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-.+ answered Local/\d+@from-queue-(\w+);\d',1) as ts_start_attendance,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-.+ answered Local/\d+@from-queue-(\w+);\d',3) as id_caller,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-.+ answered Local/\d+@from-queue-(\w+);\d',4) as id_queue	    
    from asterisk_data   
    group by 1,2,3,4
),

URA AS (
    SELECT 
       id_call,
       id_ura,
       from_unixtime(sum(coalesce(cast(ts_start_ura as integer),0))) as ts_start_ura,
       from_unixtime(sum(coalesce(cast(ts_end_ura as integer),0))) as ts_end_ura
    FROM events_ura
    GROUP BY 1,2
),

QUEUES as (
	select 
		id_call,
		--id_queue,
		id_caller,
		from_unixtime(sum(coalesce(cast(ts_start_queue as integer),0))) as ts_start_queue,
        from_unixtime(sum(coalesce(cast(ts_end_queue as integer),0))) as ts_end_queue
    from
       events_queue
    group by
     	1,2
)

SELECT
    id_c.id_call,
    u.id_ura,
    u.ts_start_ura,
    u.ts_end_ura,
    --q.id_queue,
    q.id_caller,
    q.ts_start_queue,
    q.ts_end_queue,
    a.ts_start_attendance,
    date_diff('second', u.ts_start_ura, u.ts_end_ura) as seconds_time_ura,
    date_diff('second', q.ts_start_queue, q.ts_end_queue) as seconds_time_queue
FROM
    ids_calls id_c
LEFT JOIN QUEUES q ON id_c.id_call=q.id_call
LEFT JOIN URA u ON id_c.id_call=u.id_call
LEFT JOIN events_attendance a ON id_c.id_call=a.id_call and q.id_caller = a.id_caller 
WHERE id_c.id_call IS NOT NULL
