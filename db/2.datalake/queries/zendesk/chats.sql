with chats as -- get all chat_histories
(
	select 
		id, 
		zendesk_ticket_id, 
		from_iso8601_timestamp(timestamp) as chat_start_timestamp,
		from_iso8601_timestamp(end_timestamp) as chat_end_timestamp,
		missed,
		unread,
		started_by,
		rating,
		substr(comment, 1,255) as comment,
		department_name,
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
		row_number() over (partition by id, extracted_date, (h.name = visitor.name), h.type order by h.timestamp asc)  as msg_first,
		row_number() over (partition by id, extracted_date, (h.name = visitor.name), h.type order by h.timestamp desc)  as msg_last
	from 
		datalake_raw.zendesk_chats chats
	cross join 
		unnest(chats.history) as hist(h)
	where
		h.type = 'chat.msg'
	order by 
		h.timestamp
),
avg_response_times as -- calculate response time average
(
	select
		id,
		extracted_date,
		avg(diff) as avg_response_time
	from
	(
		select
			id,
			name,
			history_timestamp,
			extracted_date
			,cast(cast(is_visitor as tinyint) != lag(cast(is_visitor as tinyint)) over (partition by id, extracted_date order by history_timestamp asc) as tinyint)	 as changed
			,date_diff('second', lag(history_timestamp) over (partition by id, extracted_date order by history_timestamp asc), history_timestamp) as diff
		from
		(
			select
				id,
				is_visitor,
				name,
				history_timestamp,
				extracted_date,
				-- msg_first,
				lag(name) over (partition by id, extracted_date order by history_timestamp asc)  as lag_name
			from
				chats
		) a	
	) a
	where changed = 1
	group by
		id,
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
select
	t.*,
	r.avg_response_time
from
	times_pivot t
join
	avg_response_times r
	on t.id = r.id and t.extracted_date = r.extracted_date
where
	t.extracted_date = cast('{}' as date)
	
--: examples::
--	t.id = '1708.958463.QS1g4gA4Fc0Hy'
--	t.id = '1708.958463.QSU9KMLHkRcdj'