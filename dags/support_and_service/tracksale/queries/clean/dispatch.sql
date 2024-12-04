select
	dispatch_code as id,
	campaign,
	customers,
	status,
	cast(create_time as timestamp) as ts_created,
	year,
	month,
	day
from datalake_tracksale_raw.dispatch
where year={year} and month={month} and day={day}