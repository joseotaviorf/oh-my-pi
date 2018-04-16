with counts as (
	select
		sk_user_agent as agent_id,
		u.nome as agent_name,
		r.greater_region,
		count(distinct(nullif(sk_visit,-1)))::decimal(10,4) as booked_visits,
		count(distinct(nullif(c.sk_contract,-1)))::decimal(10,4) as signed_contracts,
		count(distinct(nullif(sk_visit_date,-1))) as days_worked
	from 
		public.fact_demand liq
	left join 
		public.dim_date dd 
		on dd.sk_date = liq.sk_visit_date
	left join 
		public.dim_property p 
		on p.sk_property = liq.sk_property
	left join 
		public.dim_region r 
		on r.sk_region = p.regiao_id
	left join 
		public.dim_user u 
		on u.sk_user = liq.sk_user_agent
	left join 
		public.dim_contract c 
		on c.sk_contract = liq.sk_contract
		and c.dt_signature::date < current_date
	where 
		sk_user_agent<>-1
	and	dd."date" >= current_date - interval '6 weeks'
	and dd."date" < current_date - interval '2 weeks'
	and (liq.sk_contract_signed_date <> -1 or liq.sk_contract = -1)
	group by sk_user_agent, agent_name, r.greater_region
),
ratios as (
	select
		*,
		round((booked_visits/NULLIF(signed_contracts,0))::decimal(10,4),1) as visit_to_contract_ratio
	from
		counts
),
ranks as (
	select
		*,
		(rank() over (partition by greater_region order by visit_to_contract_ratio))::decimal(10,2) as weekly_rank,
		(100*percent_rank() over (partition by greater_region order by visit_to_contract_ratio))::decimal(10,2) as top_percentile,
		round((sum(booked_visits) over (partition by greater_region)/sum(signed_contracts) over (partition by greater_region))::decimal(10,4),1) as average_ratio
	from
		ratios
	where
		booked_visits >= 50
),
commission as (
	select
		*,
		case
			when round(average_ratio*1.5,1) <= visit_to_contract_ratio then 1
			when visit_to_contract_ratio is null then 1
			else 0
		end as yellow_flag,
		case
			when top_percentile between 0 and 15 then 0.3
			when top_percentile between 15 and 30 then 0.25
			else 0.20
		end as commission
	from
		ranks
),
limits as (
	select
		greater_region,
		commission,
		max(visit_to_contract_ratio) as threshold
	from
		commission
	group by greater_region, commission
)
select
  coalesce(to_char((current_date)::date,'YYYYMMDD')::integer, -1) as sk_date,
	c.agent_id as agent_id,
	c.agent_name as agent_name,
	c.greater_region as greater_region,
	c.booked_visits as bookings,
	c.signed_contracts as contracts,
	c.visit_to_contract_ratio as conversion,
	c.weekly_rank as ranking,
	c.average_ratio as average_conversion,
	c.top_percentile as top_percentile,
	c.yellow_flag as yellow_flag,
	c.commission as commission,
	gold.threshold as gold_threshold,
	silver.threshold as silver_threshold,
	round(c.average_ratio*1.5, 1) as yellow_flag_threshold,
	current_date as dt_ranking
from
	commission c
left join
	limits gold
	on gold.greater_region = c.greater_region
	and gold.commission = 0.3
left join
	limits silver
	on silver.greater_region = c.greater_region
	and silver.commission = 0.25