with asterisk_data as (
	select dt, content from datalake_raw.asterisk_logs_full
	where dt = '{partition_date}'
),
ids_calls as (
	select
		min(regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 1)) as ts_created,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 2) as id_call
	from asterisk_data
	where regexp_like(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)')=true
	group by 2
),
first_event_started as (
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
		min(regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)', 1)) as ts_created,
		now() as ts_load    
	from asterisk_data	
	where regexp_like(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(\w+)')=true
	group by 1,2,3,4,5,7
),
call_started as (
	select
		e.id_call,
		e.id_phase,
		e.phase,
		e.name,
		-- according to order: (1) ura (incoming_call), (2) queue (incoming_call_directly) and  (3) attendance (made_call) 
		-- it's necessary when ts_created is the same
		min(e.params) as params, 
		e.ts_created,
		e.ts_load
	from first_event_started e
	inner join ids_calls id_c
		on id_c.id_call=e.id_call and e.ts_created=id_c.ts_created
	where e.params is not null
	group by 1,2,3,4,6,7
),
hung_up as (
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
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)', 1) as ts_created,
		now() as ts_load
	from asterisk_data
	where regexp_like(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+NoOp\("(PJSIP|SIP|Local)/\d+(@from-queue)?-(\w+)", "(HANGUP CAUSE: \d+)"\)')=true
	group by 1,2,3,4,5,6,7
),
ura_started as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "(NOW=\d+)"', 2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "(NOW=\d+)"', 3) as id_phase,
		'ura' as phase,
		'ura_started' as name,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "(NOW=\d+)"', 4) as params,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "(NOW=\d+)"', 1) as ts_created,
		now() as ts_load
	from asterisk_data
	where regexp_like(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("SIP/\d+-(\w+)", "(NOW=\d+)"')=true
	group by 1,2,3,4,5,6,7
),
crm_source_set as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(PJSIP|SIP|Local)/(\d+)(@from-queue)?-(\w+)(;\d)?", "(__CRM_SOURCE=\d+)"', 2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(PJSIP|SIP|Local)/(\d+)(@from-queue)?-(\w+)(;\d)?", "(__CRM_SOURCE=\d+)"', 6) as id_phase,
		case
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(PJSIP|SIP|Local)/(\d+)(@from-queue)?-(\w+)(;\d)?", "(__CRM_SOURCE=\d+)"', 3)='SIP' then 'ura'
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(PJSIP|SIP|Local)/(\d+)(@from-queue)?-(\w+)(;\d)?", "(__CRM_SOURCE=\d+)"', 3)='Local' then 'queue'
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(PJSIP|SIP|Local)/(\d+)(@from-queue)?-(\w+)(;\d)?", "(__CRM_SOURCE=\d+)"', 3)='PJSIP' then 'attendance'
		end as phase,
		'crm_source_set' as name,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(PJSIP|SIP|Local)/(\d+)(@from-queue)?-(\w+)(;\d)?", "(__CRM_SOURCE=\d+)"', 8) as params,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(PJSIP|SIP|Local)/(\d+)(@from-queue)?-(\w+)(;\d)?", "(__CRM_SOURCE=\d+)"', 1) as ts_created,
		now() as ts_load
	from asterisk_data
	where regexp_like(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(PJSIP|SIP|Local)/(\d+)(@from-queue)?-(\w+)(;\d)?", "(__CRM_SOURCE=\d+)"')=true
	group by 1,2,3,4,5,6,7
),
queue_started as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 3) as id_phase,
		'queue' as phase,  
		'queue_started' as name,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 4) as params,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"', 1) as ts_created,
		now() as ts_load
	from asterisk_data
	where regexp_like(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QAGENT=\d+)"')=true
	group by 1,2,3,4,5,6,7
),
queue_num_set as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QUEUENUM=\d+)"', 2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QUEUENUM=\d+)"', 3) as id_phase,
		'queue' as phase,  
		'queue_number_set' as name,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QUEUENUM=\d+)"', 4) as params,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QUEUENUM=\d+)"', 1) as ts_created,
		now() as ts_load
	from asterisk_data
	where regexp_like(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("Local/\d+@from-queue-(\w+);\d", "(QUEUENUM=\d+)"')=true	
	group by 1,2,3,4,5,6,7
),
crm_destination_set as ( -- only to calls made by agents
    select
        regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("PJSIP/\d+-(\w+)", "(__CRM_DESTINATION=\d+)"\) in new stack', 2) as id_call,
        regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("PJSIP/\d+-(\w+)", "(__CRM_DESTINATION=\d+)"\) in new stack', 3) as id_phase,
		'attendance' as phase,
		'dest_number_set' as name,
		regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("PJSIP/\d+-(\w+)", "(__CRM_DESTINATION=\d+)"\) in new stack', 4) as params,
		regexp_extract(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("PJSIP/\d+-(\w+)", "(__CRM_DESTINATION=\d+)"\) in new stack', 1) as ts_created,
		now() as ts_load
    from asterisk_data
	where regexp_like(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("PJSIP/\d+-(\w+)", "(__CRM_DESTINATION=\d+)"\) in new stack')=true		 
    group by 1,2,3,4,5,6,7   
),
events_attendance as (
	select 
	    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',3) as id_agent,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',4) as id_attendance,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',5) as id_queue,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d',1) as ts_created,
		now() as ts_load	    
    from asterisk_data   
	where regexp_like(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] app_dial.c: PJSIP/(\d+)-(\w+) answered Local/\d+@from-queue-(\w+);\d')=true
    group by 1,2,3,4,5,6
),
attendance_started as (
	select
		id_call,
		id_attendance as id_phase,
		'attendance' as phase,
		'attendance_started' as name,
		concat('ID_QUEUE=',id_queue) as params,
		ts_created,
		ts_load
	from events_attendance
	group by 1,2,3,4,5,6,7
),
agent_answered as (
	select
		id_call,
		id_attendance as id_phase,
		'attendance' as phase,
		'agent_answered' as name,
		concat('QAGENT=',id_agent) as params,
		ts_created,
		ts_load
	from events_attendance
	group by 1,2,3,4,5,6,7
),
key_typed as (
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
        regexp_extract(content,'\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)', 1) as ts_created,
		now() as ts_load
	from asterisk_data
	where regexp_like(content, '\[(.+)\] DTMF\[[0-9]+\]\[C-(\w+)\] channel.c: DTMF begin .(\d). received on (SIP|PJSIP|Local)/\d+(@from-queue)?-(\w+)')=true
	group by 1,2,3,4,5,6,7
),
audio_message_started as (
  	select
    	regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<(SIP|PJSIP)/\d+-(\w+)> Playing .?(.custom/)?(.+)\.(ulaw.?|gsm).*', 2) as id_call,
    	regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<(SIP|PJSIP)/\d+-(\w+)> Playing .?(.custom/)?(.+)\.(ulaw.?|gsm).*', 4) as id_phase,
		case 
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<(SIP|PJSIP)/\d+-(\w+)> Playing .?(.custom/)?(.+)\.(ulaw.?|gsm).*', 3)='SIP' then 'ura'
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<(SIP|PJSIP)/\d+-(\w+)> Playing .?(.custom/)?(.+)\.(ulaw.?|gsm).*', 3)='PJSIP' then 'attendance' 
		end as phase,
		'audio_message_started' as name, 
    	regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<(SIP|PJSIP)/\d+-(\w+)> Playing .?(.custom/)?(.+)\.(ulaw.?|gsm).*', 6) as params,
    	regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<(SIP|PJSIP)/\d+-(\w+)> Playing .?(.custom/)?(.+)\.(ulaw.?|gsm).*', 1) as ts_created,
		now() as ts_load
  	from asterisk_data
	where regexp_like(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+<(SIP|PJSIP)/\d+-(\w+)> Playing .?(.custom/)?(.+)\.(ulaw.?|gsm).*')=true
  	group by 1,2,3,4,5,6,7
),
queue_join_time_set as (
	   select
	    regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(PJSIP|SIP|Local)/(\d+)(@from-queue)?-(\w+)(;\d)?", "QUEUEJOINTIME=\d+"', 2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(PJSIP|SIP|Local)/(\d+)(@from-queue)?-(\w+)(;\d)?", "QUEUEJOINTIME=\d+"', 6) as id_phase,
		case 
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(PJSIP|SIP|Local)/(\d+)(@from-queue)?-(\w+)(;\d)?", "QUEUEJOINTIME=\d+"', 3)='SIP' then 'ura'
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(PJSIP|SIP|Local)/(\d+)(@from-queue)?-(\w+)(;\d)?", "QUEUEJOINTIME=\d+"', 3)='Local' then 'queue'
			when regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(PJSIP|SIP|Local)/(\d+)(@from-queue)?-(\w+)(;\d)?", "QUEUEJOINTIME=\d+"', 3)='PJSIP' then 'attendance'			
		end as phase,
		'queue_join_time_set' as name,
        concat('CALLERID=',
			   regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(PJSIP|SIP|Local)/(\d+)(@from-queue)?-(\w+)(;\d)?", "QUEUEJOINTIME=\d+"', 4)) as params,
        regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\].+Set\("(PJSIP|SIP|Local)/(\d+)(@from-queue)?-(\w+)(;\d)?", "QUEUEJOINTIME=\d+"', 1) as ts_created,
		now() as ts_load
    from asterisk_data
    group by 1,2,3,4,5,6,7
),
queue_hung_up as (
	select
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] pbx.c: Executing .+Hangup\("Local/(\d+)@from-queue-(\w+);\d"', 2) as id_call,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] pbx.c: Executing .+Hangup\("Local/(\d+)@from-queue-(\w+);\d"', 4) as id_phase,
		'queue' as phase,
		'queue_hung_up' as name,
		concat('QAGENT=',
				regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] pbx.c: Executing .+Hangup\("Local/(\d+)@from-queue-(\w+);\d"', 3)) as params,
		regexp_extract(content,'\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] pbx.c: Executing .+Hangup\("Local/(\d+)@from-queue-(\w+);\d"', 1) as ts_created,
		now() as ts_load
	from asterisk_data
	where regexp_like(content, '\[(.+)\] VERBOSE\[[0-9]+\]\[C-(\w+)\] pbx.c: Executing .+Hangup\("Local/(\d+)@from-queue-(\w+);\d"')=true
	group by 1,2,3,4,5,6,7
)
select
	e.id_call,
	concat(id.id_call, date_format(
		   cast(concat(id.ts_created,' ','America/Sao_Paulo') as timestamp) at time zone 'UTC',
		   '%Y%m%d%H%i%s')) as sk_call,
	e.id_phase,
	e.phase,
	e.name,
	e.params,
	cast(
		cast(concat(e.ts_created,' ','America/Sao_Paulo') as timestamp) at time zone 'UTC' 
		as varchar) as ts_created,
	e.ts_load
from "{event}" e
inner join ids_calls id 
on e.id_call=id.id_call
   and date(cast(e.ts_created as timestamp))=date(cast(id.ts_created as timestamp))
   and e.ts_created >= id.ts_created
where e.id_call is not null 
	  and e.id_phase is not null;
