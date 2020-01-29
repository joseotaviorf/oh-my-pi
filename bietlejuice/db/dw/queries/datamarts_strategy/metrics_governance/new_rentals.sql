select
	coalesce(dc.dt_start, dc.dt_entrance) as rental_date,
	date_trunc('week',coalesce(dc.dt_start, dc.dt_entrance)) as rental_week_start,
	date_trunc('month',coalesce(dc.dt_start, dc.dt_entrance)) as rental_month_start,
	hl.sk_region,
	count(distinct dc.sk_contract) as new_rentals_daily,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('week',coalesce(dc.dt_start, dc.dt_entrance)), hl.sk_region) as new_rentals_weekly,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',coalesce(dc.dt_start, dc.dt_entrance)), hl.sk_region) as new_rentals_monthly
from dim_contract dc
left join fact_house_listings hl
  on dc.sk_contract = hl.sk_contract
where dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
  and date(coalesce(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
  and (date(coalesce(dc.dt_start, dc.dt_entrance)) < dc.dt_annulment or dc.dt_annulment is null) -- consider only contracts that weren't annulled before start date
group by 1, 2, 3, 4
order by 1 desc, 2, 3, 4