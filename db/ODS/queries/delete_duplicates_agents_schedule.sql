with to_mantain as
(
	select 
		a.available_date,
		count(distinct "timestamp") as qt,
		min("timestamp") as ts
	from 
		agents_schedule a
	group by 
		a.available_date
	having count(distinct "timestamp") > 1
),
to_delete as
(
	select distinct
		a.available_date,
		a."timestamp",
		m.ts,
		a."timestamp" != m.ts as del 
	from 
		agents_schedule a
	inner join
		to_mantain m
		on a.available_date = m.available_date
)
delete from
	agents_schedule a
where
	available_date::varchar || "timestamp"::varchar in
	(
		select
			available_date::varchar || "timestamp"::varchar as hash
		from
			to_delete
		where
			del = true			
	);