select
	count(1) as daily_total
from
	datalake_raw.crawler_locations
where
	cast(cast(dt_gaddress as timestamp) as date) = current_date