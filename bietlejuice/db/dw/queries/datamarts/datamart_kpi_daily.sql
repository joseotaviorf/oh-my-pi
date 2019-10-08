with
ongoing_contracts_daily as (
select
  dd.date,
  dr.sk_region,
  count(distinct dc.sk_contract) as ongoing_contracts_daily
from dim_contract dc
join dim_date dd
  on dd.date between date(coalesce(coalesce(dc.ts_signature,dc.dt_start),dc.dt_entrance)) and (coalesce(dc.dt_annulment, CURRENT_DATE) - 1)
left join fact_listing_rent_flows rf
  on dc.sk_contract = rf.sk_contract
left join dim_region dr
  on rf.sk_region = dr.sk_region
where (dc.dt_annulment < current_date OR dc.dt_annulment is null) -- we know we may have future dates for dt_annulment
  and dc.status in ('Ativo','Finalizado') -- consider only contracts that are active or were active and ended
group by 1, 2
order by 1 desc, 2
),
ongoing_rentals_daily as (
select
	  dd.date,
	  rf.sk_region,
	  count(distinct dc.sk_contract) as ongoing_rentals_daily
from dim_contract dc
join dim_date dd
  on dd.date between date(coalesce(dc.dt_start, dc.dt_entrance)) and (coalesce(dc.dt_annulment, current_date) - interval '1 day')
left join fact_listing_rent_flows rf
  on dc.sk_contract = rf.sk_contract and sk_contract_signed_date > 0
where dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
  and date(coalesce(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
  and (dc.dt_annulment < current_date OR dc.dt_annulment is null) -- we know we may have future dates for dt_annulment
  and type <> 'DealOnly'
group by 1, 2
order by 1 desc, 2
),
new_rentals as (
select
	coalesce(dc.dt_start, dc.dt_entrance) as rental_date,
	date_trunc('week',coalesce(dc.dt_start, dc.dt_entrance)) as rental_week_start,
	date_trunc('month',coalesce(dc.dt_start, dc.dt_entrance)) as rental_month_start,
	rf.sk_region,
	count(distinct dc.sk_contract) as new_rentals_daily,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('week',coalesce(dc.dt_start, dc.dt_entrance)), rf.sk_region) as new_rentals_weekly,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',coalesce(dc.dt_start, dc.dt_entrance)), rf.sk_region) as new_rentals_monthly
from dim_contract dc
left join fact_listing_rent_flows rf
  on dc.sk_contract = rf.sk_contract
where dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
  and date(coalesce(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
group by 1, 2, 3, 4
order by 1 desc, 2, 3, 4
),
new_contracts as (
select
  date(coalesce(dc.ts_signature, dc.dt_start)) as contract_signed_date,
  date_trunc('week',coalesce(dc.ts_signature, dc.dt_start)) as contract_week_start,
  date_trunc('month',coalesce(dc.ts_signature, dc.dt_start)) as contract_month_start,
  rf.sk_region,
  count(distinct dc.sk_contract) as new_contracts_signed_daily,
  sum(count(distinct dc.sk_contract)) over(partition by date_trunc('week',coalesce(dc.ts_signature, dc.dt_start)), rf.sk_region) as new_contracts_signed_weekly,
  sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',coalesce(dc.ts_signature, dc.dt_start)), rf.sk_region) as new_contracts_signed_monthly
from dim_contract dc
left join public.fact_listing_rent_flows rf
  on dc.sk_contract = rf.sk_contract
  where dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active and ended
group by 1, 2, 3, 4
order by 1 desc, 2, 3, 4
),
new_first_listings as (
select
    dd.date as first_listing_date,
    date_trunc('week', dd.date) as first_listing_week_start,
    date_trunc('month', dd.date) as first_listing_month_start,
    lf.sk_region,
    count(distinct lf.sk_house_listing) as new_first_listings_daily,
    sum(count(distinct lf.sk_house_listing)) over(partition by date_trunc('week',dd.date), lf.sk_region) as new_first_listings_weekly,
    sum(count(distinct lf.sk_house_listing)) over(partition by date_trunc('month',dd.date), lf.sk_region) as new_first_listings_monthly
from public.fact_house_listing_flows lf
  join dim_date dd
  on lf.sk_first_listing_date = dd.sk_date
  and dd.date < current_date
  where lf.sk_first_listing_date > 0
group by 1, 2, 3, 4
order by 1 desc, 2, 3, 4
),
ended_rentals as (
select
	dc.dt_annulment as date_date,
	date_trunc('week',dc.dt_annulment) as week_date,
	date_trunc('month',dc.dt_annulment) as month_date,
	rf.sk_region,
	count(distinct dc.sk_contract) as ended_rentals_daily,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('week',dc.dt_annulment), rf.sk_region) as ended_rentals_weekly,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',dc.dt_annulment), rf.sk_region) as ended_rentals_monthly
from dim_contract dc
left join fact_listing_rent_flows rf
  using(sk_contract)
where dc.status = 'Finalizado'
      and dc.dt_annulment < current_date
group by 1, 2, 3, 4
),
daily_metrics as (
select
	distinct coalesce(ocont.date,orent.date,nrent.rental_date,ncont.contract_signed_date,nfl.first_listing_date, er.date_date) as date_date,
	coalesce(ocont.sk_region,orent.sk_region,nrent.sk_region,ncont.sk_region,nfl.sk_region, er.sk_region) as sk_region,
	ocont.ongoing_contracts_daily,
	orent.ongoing_rentals_daily,
	nrent.new_rentals_daily,
	ncont.new_contracts_signed_daily,
	nfl.new_first_listings_daily,
	er.ended_rentals_daily
from ongoing_contracts_daily ocont
full outer join ongoing_rentals_daily orent
  on ocont.date = orent.date and ocont.sk_region = orent.sk_region
full outer join new_rentals nrent
  on ocont.date = nrent.rental_date and ocont.sk_region = nrent.sk_region
full outer join new_contracts ncont
  on ocont.date = ncont.contract_signed_date and ocont.sk_region = ncont.sk_region
full outer join new_first_listings nfl
  on ocont.date = nfl.first_listing_date and ocont.sk_region = nfl.sk_region
full outer join ended_rentals er
  on ocont.date = er.date_date and ocont.sk_region = er.sk_region
)
select
	dm.date_date,
	dr.regional,
	dr.city_group,
	dr.city_name,
	sum(dm.ongoing_contracts_daily) as ongoing_contracts_daily,
	sum(dm.ongoing_rentals_daily) as ongoing_rentals_daily,
	sum(dm.new_rentals_daily) as new_rentals,
	sum(dm.new_contracts_signed_daily) as new_contracts_signed,
	sum(dm.new_first_listings_daily) as new_first_listings,
	sum(dm.ended_rentals_daily) as ended_rentals
from daily_metrics dm
left join dim_region dr
  using(sk_region)
group by 1, 2, 3, 4;