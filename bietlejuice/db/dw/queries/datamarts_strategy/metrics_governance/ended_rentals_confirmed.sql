select
	date(coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)) as date_date,
	date_trunc('week',coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)) as week_date,
	date_trunc('month',coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)) as month_date,
	hl.sk_region,
	count(distinct dc.sk_contract) as ended_rentals_confirmed_daily,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('week',coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)), hl.sk_region) as ended_rentals_confirmed_weekly,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)), hl.sk_region) as ended_rentals_confirmed_monthly
from dim_contract dc
left join fact_house_listings hl
  using(sk_contract)
where dc.status = 'Finalizado'
      and coalesce(ts_analyst_annulment_input,dc.dt_annulment) < current_date
group by 1, 2, 3, 4;

