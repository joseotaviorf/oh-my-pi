with asterisk_data as (
    select dt, content from datalake_raw.asterisk_logs_full
    where date(from_iso8601_timestamp(dt)) = date('2019-03-19')
),
ids_calls as (
    select
        min(regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 1)) as time_ocurred,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 2) as id_call
    from asterisk_data
    group by 2
),
event_start_call as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 2) as id_call,
	    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 2) as id_stage,
	    'call' as desc_stage,
	    'call_started' as desc_event,
	    case
	    	when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 3)='SIP' then 'call_received'
	    	when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 3)='PJSIP' then 'call_realized'
	    	when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 3)='Local' then 'call_direct_received'
	    end as value_event,
		min(regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 1)) as time_ocurred    
	from asterisk_data
	right join ids_calls id_c
	on (id_call=id_c.id_call and time_ocurred=id_c.time_ocurred)
	group by 1,2,3,4,5
),
event_end_call as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)', 2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)', 5) as id_stage,
		case 
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)', 3)='SIP' then 'ura'
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)', 3)='PJSIP' then 'attendance'
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)', 3)='Local' then 'queue'
			else 'call'
		end as desc_stage,			
		'hangup' as desc_event,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)', 6) as value_event,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)', 1) as time_ocurred
	from asterisk_data
	where content like '%HANGUP CAUSE:%'
	group by 1,2,3,4,5,6
),
event_start_ura as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "(__CRM_SOURCE=\d+)"', 2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "(__CRM_SOURCE=\d+)"', 3) as id_stage,
		'ura' as desc_stage,
		'ura_started' as desc_event,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "(__CRM_SOURCE=\d+)"', 4) as value_event,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "(__CRM_SOURCE=\d+)"', 1) as time_ocurred
	from asterisk_data
	where content like '%__CRM_SOURCE%' and content like '%SIP%'
	group by 1,2,3,4,5,6
),

events_queue as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 3) as id_stage,
		'queue' as desc_stage,  
		'queue_started' as desc_event,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 4) as value_event,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 1) as time_ocurred
	from asterisk_data
	where content like '%Local%'
	group by 1,2,3,4,5,6
),
event_start_queue as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 3) as id_stage,
		'queue' as desc_stage,  
		'queue_started' as desc_event,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 4) as value_event,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 1) as time_ocurred
	from asterisk_data
	where content like '%QAGENT%'
	group by 1,2,3,4,5,6
),
event_set_num_queue as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QUEUENUM=\d+)"', 2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QUEUENUM=\d+)"', 3) as id_stage,
		'queue' as desc_stage,  
		'queue_number_setted' as desc_event,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QUEUENUM=\d+)"', 4) as value_event,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QUEUENUM=\d+)"', 1) as time_ocurred
	from asterisk_data
	where content like '%QUEUENUM%'
	group by 1,2,3,4,5,6
),
event_set_destination as ( -- only to calls made by agents
    select
        regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("PJSIP/\d+-(\w+)", "(__CRM_DESTINATION=\d+)"\) in new stack', 2) as id_call,
        regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("PJSIP/\d+-(\w+)", "(__CRM_DESTINATION=\d+)"\) in new stack', 3) as id_stage,
		'attendance' as desc_stage,
		'dest_number_setted' as desc_event,
		regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("PJSIP/\d+-(\w+)", "(__CRM_DESTINATION=\d+)"\) in new stack', 4) as event_value,
		regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("PJSIP/\d+-(\w+)", "(__CRM_DESTINATION=\d+)"\) in new stack', 1) as time_ocurred
    from asterisk_data
    group by 1,2    
),
events_attendance as (
	select 
	    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',3) as id_agent,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',4) as id_attendance,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',5) as id_queue,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',1) as time_ocurred	    
    from asterisk_data   
    group by 1,2,3,4,5
),
event_start_attendance as (
	select
		id_call,
		id_attendance as id_stage,
		'attendance' as desc_stage,
		'attendance_started' as desc_event,
		concat('ID_QUEUE=',id_queue) as value_event,
		time_ocurred
	from events_attendance
	group by 1,2,3,4,5,6
),
event_answered_attendance as (
	select
		id_call,
		id_attendance as id_stage,
		'attendance' as desc_stage,
		'agent_answered' as desc_event,
		concat('QAGENT=',id_agent) as value_event,
		time_ocurred
	from events_attendance
	group by 1,2,3,4,5,6
),
event_key_typed as (
  select 
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)', 2) as id_call,  
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)', 6) as id_stage, 
		case 
			when regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)', 4)='SIP' then 'ura'
			when regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)', 4)='Local' then 'queue'
			when regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)', 4)='PJSIP' then 'attendance'
		end as desc_stage,	
		'key_typed'as desc_event,          
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)', 3) as value_event,
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)', 1) as time_ocurred
  from asterisk_data
  group by 1,2,3,4,5,6
)


select * from event_start_call where id_call is not null 
union select * from event_end_call where id_call is not null  
union select * from event_start_ura where id_call is not null and id_stage is not null 
union select * from event_start_queue where id_call is not null and id_stage is not null
union select * from event_set_num_queue where id_call is not null and id_stage is not null and event_value is not null
union select * from event_start_attendance where id_call is not null and id_stage is not null 
union select * from event_answered_attendance where id_call is not null and id_stage is not null
union select * from event_key_typed where id_call is not null and id_stage is not null
union select * from event_set_destination where id_call is not null and id_stage is not null and event_value is not null
;