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
	    'start_call' as desc_event,
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
	group by 1,2,3,4,5,6
)
select * from event_start_call where id_call is not null 
union select * from event_end_call where id_call is not null;