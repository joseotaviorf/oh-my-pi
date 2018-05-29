with reg as (
select
	coalesce(to_char(r.dt::DATE,'YYYYMMDD')::integer, -1) as sk_date,
	dadosagente_id as sk_dadosagente_id,
	regioes,
	area,
	secondary_area
from staging.agent_region_group r
)
select
	cast(sk_date as char(8)) +
	cast(sk_dadosagente_id as char(8)) as sk_agentregiongroup_id,
	*
from reg