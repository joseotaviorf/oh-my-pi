with counts as (
	select
		sk_user_agent as agent_id,
		u.nome as agent_name,
		r.greater_region,
		count(distinct(nullif(sk_visit,-1)))::decimal(10,4) as booked_visits,
		count(distinct(nullif(sk_contract,-1)))::decimal(10,4) as signed_contracts,
		count(distinct(nullif(sk_visit_date,-1))) as days_worked
	from
		public.fact_liquidity_property_scheduling liq
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
	where
		sk_user_agent<>-1
	and	dd."date" >= current_date - interval '3 day' - interval '6 weeks'
	and dd."date" < current_date - interval '3 day' - interval '2 weeks'
	and (sk_contract_signed_date <> -1 or sk_contract = -1)
	group by sk_user_agent, agent_name, r.greater_region
),
ratios as (
	select
		*,
		nullif(signed_contracts,0)/4 as contract_throughput,
		(booked_visits/days_worked)::decimal(10,2) as visit_to_wdays_ratio,
--		coalesce((booked_visits/NULLIF(signed_contracts,0))::decimal(10,4),99999) as visit_to_contract_ratio,
		coalesce((NULLIF(signed_contracts,0)/booked_visits)::decimal(10,4),0) as contract_to_visit_ratio,
		sum(signed_contracts) over (partition by greater_region) as total_contracts
	from
		counts
),
ranks as (
	select
		*,
--		(rank() over (partition by greater_region order by visit_to_contract_ratio))::decimal(10,2) as weekly_rank,
		(rank() over (partition by greater_region order by contract_to_visit_ratio desc))::decimal(10,2) as weekly_rank,
		(100*percent_rank() over (partition by greater_region order by contract_to_visit_ratio desc))::decimal(10,2) as top_percentile,
		(avg(contract_to_visit_ratio) over (partition by greater_region))::decimal(10,4) as average_ratio
	from
		ratios
	where
		booked_visits >= 50
--		signed_contracts >= 4
),
commission as (
	select
		*,
		case
			when average_ratio*0.5 >= contract_to_visit_ratio then 1
			when contract_to_visit_ratio is null then 1
			else 0
		end as yellow_flag,
		case
			when top_percentile between 0 and 15 then 0.3
			when top_percentile between 15 and 30 then 0.25
			else 0.20
		end as commission,
		case
			when top_percentile between 0 and 10 then 0.3
			when top_percentile between 10 and 20 then 0.25
			else 0.20
		end as commission2
	from
		ranks
)
select
	-- id para juntar com liquidity
	agent_id,
--	agent_name,
--	greater_region,
	booked_visits as nv,
	signed_contracts as nc ,
	contract_throughput as tput,
	contract_to_visit_ratio as c2vr,
--	visit_to_contract_ratio as v2cr,
	visit_to_wdays_ratio as v2wr,
	weekly_rank as wr,
	top_percentile as per,
	average_ratio as avgr,
	yellow_flag as yf,
	commission as comm1530,
	commission2 as comm1020,
	days_worked,
	(100*sum(signed_contracts) over (partition by greater_region,commission order by weekly_rank rows unbounded preceding)/total_contracts)::decimal(10,2) as pcontracts,
	(current_date - interval '2 day')::date as rank_date
from
	commission
order by greater_region, weekly_rank
