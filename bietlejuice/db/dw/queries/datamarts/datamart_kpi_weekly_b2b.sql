with ongoing_contracts_weekly as (
select
  dd.week_start,
  fhl.sk_partner,
  fhl.sk_region,
  count(distinct dc.sk_contract) as ongoing_contracts_weekly
from dim_contract dc
join dim_date dd
  on dd.date between date(coalesce(coalesce(dc.ts_signature,dc.dt_start),dc.dt_entrance)) and (coalesce(dc.dt_annulment, CURRENT_DATE) - 1)
left join fact_house_listings fhl
  on fhl.sk_contract = dc.sk_contract
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhl.sk_house_listing
where (dc.dt_annulment < current_date OR dc.dt_annulment is null) -- we know we may have future dates for dt_annulment
  and dc.status in ('Ativo','Finalizado') -- consider only contracts that are active or were active and ended
  and dd.weekday_name = 'Sunday'
  and dhl.is_b2b = True
  and type <> 'DealOnly' -- this type of contract should only be considered for new contracts signed
group by 1, 2, 3
),
ongoing_rentals_weekly as (
select
	  dd.week_start,
	  fhl.sk_partner,
	  fhl.sk_region,
	  count(distinct dc.sk_contract) as ongoing_rentals_weekly
from dim_contract dc
join dim_date dd
  on dd.date between date(coalesce(dc.dt_start, dc.dt_entrance)) and (coalesce(dc.dt_annulment, current_date) - interval '1 day')
left join fact_house_listings fhl
  on fhl.sk_contract = dc.sk_contract
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhl.sk_house_listing
where dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
  and dd.weekday_name = 'Sunday' -- only look last day of the week
  and date(coalesce(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
  and (dc.dt_annulment < current_date OR dc.dt_annulment is null) -- we know we may have future dates for dt_annulment
  and type <> 'DealOnly'
  and dhl.is_b2b = True
group by 1, 2, 3
),
new_rentals as (
select
	coalesce(dc.dt_start, dc.dt_entrance) as rental_date,
	date_trunc('week',coalesce(dc.dt_start, dc.dt_entrance)) as rental_week_start,
	date_trunc('month',coalesce(dc.dt_start, dc.dt_entrance)) as rental_month_start,
	fhl.sk_partner,
	fhl.sk_region,
	count(distinct dc.sk_contract) as new_rentals_daily,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('week',coalesce(dc.dt_start, dc.dt_entrance)), fhl.sk_region) as new_rentals_weekly,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',coalesce(dc.dt_start, dc.dt_entrance)), fhl.sk_region) as new_rentals_monthly
from dim_contract dc
left join fact_house_listings fhl
  on fhl.sk_contract = dc.sk_contract
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhl.sk_house_listing
where dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
  and date(coalesce(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
  and (date(coalesce(dc.dt_start, dc.dt_entrance)) < dc.dt_annulment or dc.dt_annulment is null) -- consider only contracts that weren't annulled before start date
  and dhl.is_b2b = True
group by 1, 2, 3, 4, 5
),
new_contracts as (
select
  date(coalesce(dc.ts_signature, dc.dt_start)) as contract_signed_date,
  date_trunc('week',coalesce(dc.ts_signature, dc.dt_start)) as contract_week_start,
  date_trunc('month',coalesce(dc.ts_signature, dc.dt_start)) as contract_month_start,
  fhl.sk_partner,
  fhl.sk_region,
  count(distinct dc.sk_contract) as new_contracts_signed_daily,
  sum(count(distinct dc.sk_contract)) over(partition by date_trunc('week',coalesce(dc.ts_signature, dc.dt_start)), fhl.sk_region) as new_contracts_signed_weekly,
  sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',coalesce(dc.ts_signature, dc.dt_start)), fhl.sk_region) as new_contracts_signed_monthly
from dim_contract dc
left join fact_house_listings fhl
  on fhl.sk_contract = dc.sk_contract
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhl.sk_house_listing
  where dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active and ended
  and dhl.is_b2b = True
group by 1, 2, 3, 4, 5
),
new_first_listings as (
select
    dd.date as first_listing_date,
    date_trunc('week', dd.date) as first_listing_week_start,
    date_trunc('month', dd.date) as first_listing_month_start,
    fhl.sk_partner,
    lf.sk_region,
    count(distinct lf.sk_house_listing) as new_first_listings_daily,
    sum(count(distinct lf.sk_house_listing)) over(partition by date_trunc('week',dd.date), lf.sk_region) as new_first_listings_weekly,
    sum(count(distinct lf.sk_house_listing)) over(partition by date_trunc('month',dd.date), lf.sk_region) as new_first_listings_monthly
from public.fact_house_listing_flows lf
  join dim_date dd
  on lf.sk_first_listing_date = dd.sk_date
  and dd.date < current_date
left join dim_house_listing dhl
  on dhl.sk_house_listing = lf.sk_house_listing
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing
  where lf.sk_first_listing_date > 0
   and dhl.is_b2b = True
group by 1, 2, 3, 4, 5
),
re_rentals as (
	with ordered_rentals as (
		select
			coalesce(dc.dt_start, dc.dt_entrance) as rental_date,
			date_trunc('week',coalesce(dc.dt_start, dc.dt_entrance)) as rental_week_start,
			date_trunc('month',coalesce(dc.dt_start, dc.dt_entrance)) as rental_month_start,
			fhl.sk_house_listing,
			fhl.nr_renting,
			fhl.sk_partner,
			dc.status,
			dc.sk_contract,
			row_number() over (partition by dhl.id_house order by fhl.sk_house_listing) as row_number_renting,
			fhl.sk_region
		from dim_contract dc
		join fact_house_listings fhl
		on dc.sk_contract = fhl.sk_contract
		join dim_house_listing dhl
		on dhl.sk_house_listing = fhl.sk_house_listing
		where date(coalesce(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
		and fhl.nr_renting > 1
		and dhl.is_b2b = True
	)
	select
		ord.rental_date,
		ord.rental_week_start,
		ord.rental_month_start,
		ord.sk_partner,
		ord.sk_region,
		count(distinct ord.sk_contract) as re_rentals_daily,
		sum(count(distinct ord.sk_contract)) over(partition by date_trunc('week',ord.rental_week_start), ord.sk_region) as re_rentals_weekly,
		sum(count(distinct ord.sk_contract)) over(partition by date_trunc('month',ord.rental_month_start), ord.sk_region) as re_rentals_monthly
	from ordered_rentals ord
	where ord.row_number_renting > 1 and ord.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
	group by 1, 2, 3, 4, 5
),
ended_rentals as (
select
	dc.dt_annulment as date_date,
	date_trunc('week',dc.dt_annulment) as week_date,
	date_trunc('month',dc.dt_annulment) as month_date,
	fhl.sk_partner,
	fhl.sk_region,
	count(distinct dc.sk_contract) as ended_rentals_daily,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('week',dc.dt_annulment), fhl.sk_region) as ended_rentals_weekly,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',dc.dt_annulment), fhl.sk_region) as ended_rentals_monthly
from dim_contract dc
left join fact_house_listings fhl
  on fhl.sk_contract = dc.sk_contract
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhl.sk_house_listing
where dc.status = 'Finalizado'
      and dc.dt_annulment < current_date
      and dhl.is_b2b = True
group by 1, 2, 3, 4, 5
),
ended_rentals_confirmed as (
select
	date(coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)) as date_date,
	date_trunc('week',coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)) as week_date,
	date_trunc('month',coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)) as month_date,
	fhl.sk_partner,
	fhl.sk_region,
	count(distinct dc.sk_contract) as ended_rentals_confirmed_daily,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('week',coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)), fhl.sk_region) as ended_rentals_confirmed_weekly,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)), fhl.sk_region) as ended_rentals_confirmed_monthly
from dim_contract dc
left join fact_house_listings fhl
  on fhl.sk_contract = dc.sk_contract
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhl.sk_house_listing
where dc.status = 'Finalizado'
    and dhl.is_b2b = True
	and coalesce(ts_analyst_annulment_input,dc.dt_annulment) < current_date
group by 1, 2, 3, 4, 5
),
bookers as (
select
    date_trunc('week',dd.date) as booking_created_week,
    fhl.sk_partner,
    rf.sk_region,
    count(distinct rf.sk_client) as bookers_weekly
from fact_listing_rent_flows rf
left join dim_date dd
  on rf.sk_booking_created_date = dd.sk_date
left join dim_house_listing dhl
  on dhl.sk_house_listing = rf.sk_house_listing
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing
where dhl.is_b2b = True
group by 1, 2, 3
),
new_bookers as (
	with
	first_booking as (
		select *
		from (
		    select
		    rf.ods_id,
		    rf.sk_client,
		    rf.sk_region,
		    db.dt_created as first_booking_created_date,
		    row_number() over (partition by rf.sk_client order by db.dt_created asc) as rk
		    from fact_listing_rent_flows rf
		    join dim_booking db
		    	on db.sk_booking = rf.sk_booking
		    where rf.sk_booking_created_date
		)
		where rk = 1
		)
	select
	    date_trunc('week',fb.first_booking_created_date) as first_booking_created_week,
	    fhl.sk_partner,
	    dr.sk_region,
	    count(distinct fb.sk_client) as new_bookers_weekly
	from first_booking fb
	left join fact_listing_rent_flows rf
	  on (fb.sk_client = rf.sk_client)
	left join dim_date dd
	  on rf.sk_contract_signed_date = dd.sk_date
	left join dim_region dr
	 on fb.sk_region = dr.sk_region
	left join dim_house_listing dhl
 	 on dhl.sk_house_listing = rf.sk_house_listing
 	left join fact_house_listings fhl
  	  on fhl.sk_house_listing = dhl.sk_house_listing
 	where dhl.is_b2b = True
	group by 1, 2, 3
),
ongoing_listings_weekly as (
with
daily_published_listings as (
select
    f.sk_house_listing,
    f.status_history,
    d.date,
    d.week_start,
    d.weekday_name,
    d.month_start,
    d.month_end,
    row_number() over(partition by f.sk_house_listing, d.date order by f.ts_status_start desc) as order_status -- daily order status
from fact_house_listing_status f
join dim_date d
  on d.sk_date between nullif(f.sk_status_start_date,-1) and coalesce(to_char(to_date(nullif(f.sk_status_end_date,-1),'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date -1, 'YYYYMMDD')::bigint)
left join dim_house_listing dhl
  on dhl.sk_house_listing = f.sk_house_listing
where f.status_history = 'publicado' -- consider only published status
  and dhl.is_b2b = True
  and substring(f.sk_house_listing,10,12) <> '000' -- consider only listings that already started publication
),
daily_published_listings_adjusted as (
select
    fhs.sk_house_listing,
    fhs.date,
    fhs.week_start,
    fhs.weekday_name,
    fhs.month_start,
    fhs.month_end,
    fhs.order_status,
    fhs.status_history,
    fhl.sk_region,
    fhl.sk_partner
from daily_published_listings fhs
left join fact_house_listings fhl
  on fhs.sk_house_listing = fhl.sk_house_listing
left join dim_region dr
  on fhl.sk_region = dr.sk_region
where fhs.order_status = 1
  and dr.city_group is not null
  and fhs.weekday_name = 'Sunday' -- filter that indicates it will be grouped by week
)
select
    week_start,
    sk_partner,
    sk_region,
    count(distinct sk_house_listing) as ongoing_listings_weekly
from daily_published_listings_adjusted
group by 1, 2, 3
),
weekly_metrics as (
select
	distinct coalesce(ocont.week_start,orent.week_start,nrent.rental_week_start,ncont.contract_week_start,nfl.first_listing_week_start,rr.rental_week_start, er.week_date, erc.week_date, olist.week_start, bk.booking_created_week, nbk.first_booking_created_week) as week_date,
	coalesce(ocont.sk_partner,orent.sk_partner,nrent.sk_partner,ncont.sk_partner,nfl.sk_partner, er.sk_partner,erc.sk_partner,rr.sk_partner, olist.sk_partner, bk.sk_partner, nbk.sk_partner) as sk_partner,
	coalesce(ocont.sk_region,orent.sk_region,nrent.sk_region,ncont.sk_region,nfl.sk_region,rr.sk_region, er.sk_region, erc.sk_region, olist.sk_region, bk.sk_region, nbk.sk_region) as sk_region,
	ocont.ongoing_contracts_weekly,
	orent.ongoing_rentals_weekly,
	nrent.new_rentals_weekly,
	ncont.new_contracts_signed_weekly,
	nfl.new_first_listings_weekly,
	rr.re_rentals_weekly,
	er.ended_rentals_weekly,
	erc.ended_rentals_confirmed_weekly,
	olist.ongoing_listings_weekly,
	bk.bookers_weekly,
	nbk.new_bookers_weekly
from ongoing_contracts_weekly ocont
full outer join ongoing_rentals_weekly orent
  on ocont.week_start = orent.week_start and ocont.sk_region = orent.sk_region
full outer join new_rentals nrent
  on ocont.week_start = nrent.rental_week_start and ocont.sk_region = nrent.sk_region
full outer join new_contracts ncont
  on ocont.week_start = ncont.contract_week_start and ocont.sk_region = ncont.sk_region
full outer join new_first_listings nfl
  on ocont.week_start = nfl.first_listing_week_start and ocont.sk_region = nfl.sk_region
full outer join re_rentals rr
  on ocont.week_start = rr.rental_week_start and ocont.sk_region = rr.sk_region
full outer join ended_rentals er
  on ocont.week_start = er.week_date and ocont.sk_region = er.sk_region
full outer join ended_rentals_confirmed erc
  on ocont.week_start = erc.week_date and ocont.sk_region = erc.sk_region
full outer join ongoing_listings_weekly olist
  on ocont.week_start = olist.week_start and ocont.sk_region = olist.sk_region
full outer join bookers bk
  on ocont.week_start = bk.booking_created_week and ocont.sk_region = bk.sk_region
full outer join new_bookers nbk
  on ocont.week_start = nbk.first_booking_created_week and ocont.sk_region = nbk.sk_region
)
select
	dm.week_date,
	dm.sk_partner,
	dr.regional,
	dr.city_group,
	dr.city_name,
	sum(dm.ongoing_contracts_weekly) as ongoing_contracts_weekly,
	sum(dm.ongoing_rentals_weekly) as ongoing_rentals_weekly,
	sum(dm.new_rentals_weekly) as new_rentals_weekly,
	sum(dm.new_contracts_signed_weekly) as new_contracts_signed_weekly,
	sum(dm.new_first_listings_weekly) as new_first_listings_weekly,
	sum(dm.re_rentals_weekly) as re_rentals_weekly,
	sum(dm.ended_rentals_weekly) as ended_rentals_weekly,
	sum(dm.ended_rentals_confirmed_weekly) as ended_rentals_confirmed_weekly,
	sum(dm.ongoing_listings_weekly) as ongoing_listings_weekly,
	sum(dm.bookers_weekly) as bookers_weekly,
	sum(dm.new_bookers_weekly) as new_bookers_weekly
from weekly_metrics dm
left join dim_region dr
  using(sk_region)
group by 1, 2, 3, 4, 5;