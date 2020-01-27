select
	dc.dt_annulment as date_date,
	date_trunc('week',dc.dt_annulment) as week_date,
	date_trunc('month',dc.dt_annulment) as month_date,
	hl.sk_region,
	count(distinct dc.sk_contract) as ended_rentals_daily,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('week',dc.dt_annulment), hl.sk_region) as ended_rentals_weekly,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',dc.dt_annulment), hl.sk_region) as ended_rentals_monthly
from dim_contract dc
left join fact_house_listings hl
  using(sk_contract)
where dc.status = 'Finalizado'
      and dc.dt_annulment < current_date
group by 1, 2, 3, 4;

