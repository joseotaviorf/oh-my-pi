with chats as -- get all chat_histories
(
	select
		min(id) over (partition by zendesk_ticket_id, extracted_date, h.type order by h.timestamp asc) as id, 
		zendesk_ticket_id, 
		min(from_iso8601_timestamp(timestamp)) over (partition by zendesk_ticket_id, extracted_date, h.type) as chat_start_timestamp,
		max(from_iso8601_timestamp(end_timestamp)) over (partition by zendesk_ticket_id, extracted_date, h.type) as chat_end_timestamp,
		missed,
		unread,
		started_by,
		rating,
		substring(comment, 1, 200) as comment,
		first_value(department_name) over (partition by zendesk_ticket_id, extracted_date, (h.name = visitor.name), h.type order by h.timestamp asc) as department_name,
		visitor.email, 
		visitor.name as visitor_name,
		h.name = visitor.name as is_visitor,
		type,
		h.name,
		h.type as history_type,
		h.msg,
		from_iso8601_timestamp(h.timestamp) as history_timestamp,
		response_time,
		extracted_date,
		row_number() over (partition by zendesk_ticket_id, extracted_date, (h.name = visitor.name), h.type order by h.timestamp asc)  as msg_first,
		row_number() over (partition by zendesk_ticket_id, extracted_date, (h.name = visitor.name), h.type order by h.timestamp desc)  as msg_last
	from 
		datalake_raw.zendesk_chats chats
	cross join 
		unnest(chats.history) as hist(h)
	where
		h.type = 'chat.msg'
		and zendesk_ticket_id is not null
	order by 
		h.timestamp
),
avg_response_times as -- calculate response time average
(
	select
		zendesk_ticket_id,
		extracted_date,
		avg(diff) as avg_response_time
	from
	(
		select
			zendesk_ticket_id,
			name,
			history_timestamp,
			extracted_date
			,cast(cast(is_visitor as tinyint) != lag(cast(is_visitor as tinyint)) over (partition by zendesk_ticket_id, extracted_date order by history_timestamp asc) as tinyint)	 as changed
			,date_diff('second', lag(history_timestamp) over (partition by zendesk_ticket_id, extracted_date order by history_timestamp asc), history_timestamp) as diff
		from
		(
			select
				zendesk_ticket_id,
				is_visitor,
				name,
				history_timestamp,
				extracted_date,
				-- msg_first,
				lag(name) over (partition by zendesk_ticket_id, extracted_date order by history_timestamp asc)  as lag_name
			from
				chats
		) a	
	) a
	where changed = 1
	group by
		zendesk_ticket_id,
		extracted_date
)
,times as -- get the first and last 'times' only
(
	select
		*,
		case 
			when msg_first = 1 and is_visitor = false then 'first_answer'
			when msg_first = 1 and is_visitor = true then 'first_visitor_msg'
			when msg_last = 1 and is_visitor = true then 'last_visitor_msg'
			when msg_last = 1 and is_visitor = false then 'last_answer'
		end as times_description
	from
		chats
	where
		msg_first = 1 or msg_last=1
	order by
		history_timestamp
),
times_pivot as -- pivoting times
(
	select
		*,
		times['first_visitor_msg'] as first_visitor_msg,
		times['first_answer'] as first_answer,
		times['last_answer'] as last_answer,
		times['last_visitor_msg'] as last_visitor_msg
	from
	(
		select
			id,
			zendesk_ticket_id,
			chat_start_timestamp,
			chat_end_timestamp,
			missed,
			unread,
			comment,
			department_name,
			started_by,
			rating,
			email,
			extracted_date,
			map_agg (times_description, history_timestamp) as times
		from
			times
		group by
			id,
			zendesk_ticket_id,
			chat_start_timestamp,
			chat_end_timestamp,
			missed,
			unread,
			comment,
			department_name,
			started_by,
			rating,
			email,
			extracted_date
	)
)
-- result:
select distinct
	t.id,
	t.zendesk_ticket_id as zendesk_ticket_id,
	min(t.chat_start_timestamp) as chat_start_timestamp,
	max(t.chat_end_timestamp) as chat_end_timestamp,
	first_value(missed) over (partition by t.zendesk_ticket_id) as missed,
	first_value(unread) over (partition by t.zendesk_ticket_id) as unread,
	first_value(comment) over (partition by t.zendesk_ticket_id) as comment,
	first_value(department_name) over (partition by t.zendesk_ticket_id) as department_name,
	first_value(started_by) over (partition by t.zendesk_ticket_id) as started_by,
	first_value(rating) over (partition by t.zendesk_ticket_id) as rating,
	t.email,
	t.extracted_date,
	-- first_value(times) over () as times,
	first_value(first_visitor_msg) over (partition by t.zendesk_ticket_id) as first_visitor_msg,
	first_value(first_answer) over (partition by t.zendesk_ticket_id) as first_answer,
	last_value(last_answer) over (partition by t.zendesk_ticket_id) as last_answer,
	last_value(last_visitor_msg) over (partition by t.zendesk_ticket_id) as last_visitor_msg,
	r.avg_response_time
from
	times_pivot t
join
	avg_response_times r
	on t.zendesk_ticket_id = r.zendesk_ticket_id and t.extracted_date = r.extracted_date
where
	t.extracted_date = cast('{}' as date)
	and t.zendesk_ticket_id is not null
	-- t.zendesk_ticket_id = 212249 -- exemplo de chat com o zen_ticket_id duplicado
group by
	t.id,
	t.zendesk_ticket_id,
	t.missed,
	t.unread,
	t.comment,
	t.department_name,
	t.started_by,
	t.rating,
	t.email,
	t.extracted_date,
	first_visitor_msg,
	first_answer,
	last_answer,
	last_visitor_msg,
	r.avg_response_time
	
--: examples::
--	t.id = '1708.958463.QS1g4gA4Fc0Hy'
--	t.id = '1708.958463.QSU9KMLHkRcdj'