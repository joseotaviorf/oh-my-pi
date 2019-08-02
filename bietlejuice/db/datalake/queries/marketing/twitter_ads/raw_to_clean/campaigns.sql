select
	id,
	name,
	id_account,
	account_name,
	start_time,
	end_time,
	created_at,
	updated_at,
	entity_status,
	duration_in_days,
	total_budget_amount_local_micro,
	daily_budget_amount_local_micro,
	standard_delivery,
	currency,
	servable,
	funding_instrument_id,
	reasons_not_servable,
	frequency_cap,
	to_delete,
	deleted
from datalake_raw.marketing_twitter_campaigns
WHERE dt='{date}' and acc='{account}'