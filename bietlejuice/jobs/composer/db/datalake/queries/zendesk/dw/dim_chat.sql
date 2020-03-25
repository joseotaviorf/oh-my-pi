-- get only the most recent chat loaded
with chat_max_date as (
	select 
		id,
        max(
          concat(
            string(year), 
            lpad(string(month), 2, '0'), 
            lpad(string(day), 2, '0')
           )
        ) as ts_load -- YYYYMMDD format
	from {db}.chats
	group by 1
),
-- create base table for chats (no rules applied)
chats as (
	select
		c.id,
		c.tags,
		c.started_by,
		c.visitor,
		c.is_missed,
		c.is_proactive,
		c.ts_created as ts_started,
		from_utc_timestamp(c.ts_created, 'GMT-3') as ts_started_local,
		c.ts_ended,
		from_utc_timestamp(c.ts_ended, 'GMT-3') as ts_ended_local,
		c.ts_updated
	from {db}.chats c 
	inner join chat_max_date m 
		on c.id = m.id
		and m.ts_load = concat(
            string(year), 
            lpad(string(month), 2, '0'), 
            lpad(string(day), 2, '0')
           )
	group by 1,2,3,4,5,6,7,8,9,10,11
),
business_rules as (
	select
		id,
		case when tags like '%bot_end_conversation%' then true else false end as is_retained_by_bot,
		case when is_missed = true and tags not like '%bot_end_conversation%' then true else false end as is_missed
	from chats 
),
statuses as (
    select
        b.*,
        case
            when b.is_missed = true then 'missed'
            when b.is_retained_by_bot = true then 'answered_by_bot'
            when b.is_missed = false and b.is_retained_by_bot = false then 'answered_by_agent'
	    end as status
    from business_rules b
)
select
	regexp_extract(c.id, '[^.]+$', 0) as sk_chat, --Create key by removing string prefix (year/month + default constant '958463') 
	c.tags,
	c.started_by,
	nullif(get_json_object(c.visitor, '$.phone'),'') as visitor_phone,
	s.is_retained_by_bot,
	s.is_missed,
	c.is_proactive,
	c.ts_started,
	c.ts_started_local,
	c.ts_ended,
	c.ts_ended_local,
	c.ts_updated,
    s.status,
	now() as ts_load
from chats c
inner join statuses s
	on c.id = s.id