select
	  dd.week_start,
	  hl.sk_region,
	  count(distinct dc.sk_contract) as ongoing_rentals_weekly
from dim_contract dc
join dim_date dd
  on dd.date between date(coalesce(dc.dt_start, dc.dt_entrance)) and (coalesce(dc.dt_annulment, current_date) - interval '1 day')
left join fact_house_listings hl
  on dc.sk_contract = hl.sk_contract
where dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
  and dd.weekday_name = 'Sunday' -- only look last day of the week
  and date(coalesce(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
  and dd.date < current_date -- we know we may have future dates for dt_annulment and we need to filter future dates
  and type <> 'DealOnly'
group by 1, 2
order by 1 desc, 2