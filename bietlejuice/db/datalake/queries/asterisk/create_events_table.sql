with asterisk_data as (
	select dt, content from datalake_raw.asterisk_logs_full
	where date(from_iso8601_timestamp(dt)) = date('{partition_date}')
),
ids_calls as (
	select
		min(regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 1)) as ts_ocurred,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 2) as id_call
	from asterisk_data
	where regexp_like(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)')=true
	group by 2
),
event_start_call as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 2) as id_call,
	    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 2) as id_phase,
	    'call' as phase,
	    'call_started' as name,
	    case
	    	when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 3)='SIP' then 'incoming_call'
	    	when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 3)='PJSIP' then 'made_call'
	    	when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 3)='Local' then 'incoming_call_directly'
	    end as params,
		min(regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 1)) as ts_ocurred    
	from asterisk_data
	right join ids_calls id_c
	on (id_call=id_c.id_call and ts_ocurred=id_c.ts_ocurred)
	where regexp_like(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)')=true		
	group by 1,2,3,4,5
),
event_end_call as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)', 2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)', 5) as id_phase,
		case 
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)', 3)='SIP' then 'ura'
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)', 3)='PJSIP' then 'attendance'
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)', 3)='Local' then 'queue'
			else 'call'
		end as phase,			
		'hung_up' as name,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)', 6) as params,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)', 1) as ts_ocurred
	from asterisk_data
	where regexp_like(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)')=true
	group by 1,2,3,4,5,6
),
event_start_ura as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "(__CRM_SOURCE=\d+)"', 2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "(__CRM_SOURCE=\d+)"', 3) as id_phase,
		'ura' as phase,
		'ura_started' as name,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "(__CRM_SOURCE=\d+)"', 4) as params,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "(__CRM_SOURCE=\d+)"', 1) as ts_ocurred
	from asterisk_data
	where regexp_like(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "(__CRM_SOURCE=\d+)"')=true
	group by 1,2,3,4,5,6
),
event_start_queue as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 3) as id_phase,
		'queue' as phase,  
		'queue_started' as name,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 4) as params,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 1) as ts_ocurred
	from asterisk_data
	where regexp_like(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"')=true
	group by 1,2,3,4,5,6
),
event_set_queue_num as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QUEUENUM=\d+)"', 2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QUEUENUM=\d+)"', 3) as id_phase,
		'queue' as phase,  
		'queue_number_set' as name,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QUEUENUM=\d+)"', 4) as params,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QUEUENUM=\d+)"', 1) as ts_ocurred
	from asterisk_data
	where regexp_like(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QUEUENUM=\d+)"')=true	
	group by 1,2,3,4,5,6
),
event_set_destination as ( -- only to calls made by agents
    select
        regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("PJSIP/\d+-(\w+)", "(__CRM_DESTINATION=\d+)"\) in new stack', 2) as id_call,
        regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("PJSIP/\d+-(\w+)", "(__CRM_DESTINATION=\d+)"\) in new stack', 3) as id_phase,
		'attendance' as phase,
		'dest_number_set' as type,
		regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("PJSIP/\d+-(\w+)", "(__CRM_DESTINATION=\d+)"\) in new stack', 4) as params,
		regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("PJSIP/\d+-(\w+)", "(__CRM_DESTINATION=\d+)"\) in new stack', 1) as ts_ocurred
    from asterisk_data
	where regexp_like(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("PJSIP/\d+-(\w+)", "(__CRM_DESTINATION=\d+)"\) in new stack')=true		 
    group by 1,2,3,4,5,6   
),
events_attendance as (
	select 
	    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',3) as id_agent,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',4) as id_attendance,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',5) as id_queue,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',1) as ts_ocurred	    
    from asterisk_data   
	where regexp_like(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d')=true
    group by 1,2,3,4,5
),
event_start_attendance as (
	select
		id_call,
		id_attendance as id_phase,
		'attendance' as phase,
		'attendance_started' as name,
		concat('ID_QUEUE=',id_queue) as params,
		ts_ocurred
	from events_attendance
	group by 1,2,3,4,5,6
),
event_answer_agent as (
	select
		id_call,
		id_attendance as id_phase,
		'attendance' as phase,
		'agent_answered' as name,
		concat('QAGENT=',id_agent) as params,
		ts_ocurred
	from events_attendance
	group by 1,2,3,4,5,6
),
event_key_typed as (
  	select 
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)', 2) as id_call,  
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)', 6) as id_phase, 
		case 
			when regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)', 4)='SIP' then 'ura'
			when regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)', 4)='Local' then 'queue'
			when regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)', 4)='PJSIP' then 'attendance'
		end as phase,	
		'key_typed'as name,          
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)', 3) as params,
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)', 1) as ts_ocurred
	from asterisk_data
	where regexp_like(content, '\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)')=true
	group by 1,2,3,4,5,6
),
event_audio_message as (
  	select
    	regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<(SIP|PJSIP)/\d+-(\w+)> Playing .?(.custom/)?(.+)\.(ulaw.?|gsm).*', 2) as id_call,
    	regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<(SIP|PJSIP)/\d+-(\w+)> Playing .?(.custom/)?(.+)\.(ulaw.?|gsm).*', 4) as id_phase,
		case 
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<(SIP|PJSIP)/\d+-(\w+)> Playing .?(.custom/)?(.+)\.(ulaw.?|gsm).*', 3)='SIP' then 'ura'
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<(SIP|PJSIP)/\d+-(\w+)> Playing .?(.custom/)?(.+)\.(ulaw.?|gsm).*', 3)='PJSIP' then 'attendance' 
		end as phase,
		'audio_message_started' as name, 
    	regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<(SIP|PJSIP)/\d+-(\w+)> Playing .?(.custom/)?(.+)\.(ulaw.?|gsm).*', 6) as params,
    	regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<(SIP|PJSIP)/\d+-(\w+)> Playing .?(.custom/)?(.+)\.(ulaw.?|gsm).*', 1) as ts_ocurred
  	from asterisk_data
	where regexp_like(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<(SIP|PJSIP)/\d+-(\w+)> Playing .?(.custom/)?(.+)\.(ulaw.?|gsm).*')=true
  	group by 1,2,3,4,5,6
)

select * from event_start_call where id_call is not null
union all select * from event_end_call where id_call is not null  
union all select * from event_start_ura where id_call is not null and id_phase is not null 
union all select * from event_start_queue where id_call is not null and id_phase is not null
union all select * from event_set_queue_num where id_call is not null and id_phase is not null and params is not null
union all select * from event_start_attendance where id_call is not null and id_phase is not null 
union all select * from event_answer_agent where id_call is not null and id_phase is not null
union all select * from event_key_typed where id_call is not null and id_phase is not null
union all select * from event_set_destination where id_call is not null and id_phase is not null and params is not null
union all select * from event_audio_message where id_call is not null and id_phase is not null and params is not null
;