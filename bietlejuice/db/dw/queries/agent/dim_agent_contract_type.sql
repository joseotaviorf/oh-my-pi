select
	cast(id as integer) as sk_agent_contract_type,
	cast(id as integer) as id_agent_contract_type,
	cast(slots_per_saturday as integer) as slots_per_saturday,
	cast(slots_per_weekday as integer) as slots_per_weekday,
	contract_name,
	contract_type
FROM
	datalake_clean.agent_contract_type