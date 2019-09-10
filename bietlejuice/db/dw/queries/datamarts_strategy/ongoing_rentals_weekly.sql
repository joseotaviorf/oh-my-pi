-- Define ongoing rentals weekly
-- Contracts that signed contract and didn't ended before start/entrance date
-- Contracts of type DealOnly should only be considered in the first month as a ongoing rental

select
	  dd.week_start,
	  rf.sk_region,
	  count(distinct dc.sk_contract) as ongoing_rentals_weekly
from dim_contract dc
join dim_date dd
  on dd.date between date(coalesce(dc.dt_start, dc.dt_entrance)) and (coalesce(dc.dt_annulment, current_date) - interval '1 day')
left join fact_listing_rent_flows rf
  on dc.sk_contract = rf.sk_contract and sk_contract_signed_date > 0
where dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
  and dd.weekday_name = 'Sunday' -- only look last day of the week
  and date(coalesce(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
  and (dc.dt_annulment < current_date OR dc.dt_annulment is null) -- we know we may have future dates for dt_annulment
  and type <> 'DealOnly'
group by 1, 2
order by 1 desc, 2