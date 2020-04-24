with
ongoing_contracts_daily as (
select
  dd.date,
  fhl.sk_partner,
  fhl.sk_region,
  count(distinct dc.sk_contract) as ongoing_contracts_daily
from dim_contract dc
join dim_date dd
  on dd.date between date(coalesce(coalesce(dc.ts_signature,dc.dt_start),dc.dt_entrance)) and (coalesce(dc.dt_annulment, CURRENT_DATE) - 1)
left join fact_house_listings fhl
  on fhl.sk_contract = dc.sk_contract
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhl.sk_house_listing
where dd.date < current_date -- we know we may have future dates for dt_annulment and we need to filter future dates
  and dc.status in ('Ativo','Finalizado') -- consider only contracts that are active or were active and ended
  and dhl.is_b2b = True
  and type <> 'DealOnly' -- this type of contract should only be considered for new contracts signed
group by 1, 2, 3
),
ongoing_rentals_daily as (
select
	  dd.date,
	  fhl.sk_partner,
	  fhl.sk_region,
	  count(distinct dc.sk_contract) as ongoing_rentals_daily
from dim_contract dc
join dim_date dd
  on dd.date between date(coalesce(dc.dt_start, dc.dt_entrance)) and (coalesce(dc.dt_annulment, current_date) - interval '1 day')
left join fact_house_listings fhl
  on fhl.sk_contract = dc.sk_contract
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhl.sk_house_listing
where dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
  and date(coalesce(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
  and dd.date < current_date -- we know we may have future dates for dt_annulment and we need to filter future dates
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
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('week',coalesce(dc.dt_start, dc.dt_entrance)), fhl.sk_region, fhl.sk_partner) as new_rentals_weekly,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',coalesce(dc.dt_start, dc.dt_entrance)), fhl.sk_region, fhl.sk_partner) as new_rentals_monthly
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
  sum(count(distinct dc.sk_contract)) over(partition by date_trunc('week',coalesce(dc.ts_signature, dc.dt_start)), fhl.sk_region, fhl.sk_partner) as new_contracts_signed_weekly,
  sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',coalesce(dc.ts_signature, dc.dt_start)), fhl.sk_region, fhl.sk_partner) as new_contracts_signed_monthly
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
    sum(count(distinct lf.sk_house_listing)) over(partition by date_trunc('week',dd.date), lf.sk_region, fhl.sk_partner) as new_first_listings_weekly,
    sum(count(distinct lf.sk_house_listing)) over(partition by date_trunc('month',dd.date), lf.sk_region, fhl.sk_partner) as new_first_listings_monthly
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
		sum(count(distinct ord.sk_contract)) over(partition by date_trunc('week',ord.rental_week_start), ord.sk_region, ord.sk_partner) as re_rentals_weekly,
		sum(count(distinct ord.sk_contract)) over(partition by date_trunc('month',ord.rental_month_start), ord.sk_region, ord.sk_partner) as re_rentals_monthly
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
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('week',dc.dt_annulment), fhl.sk_region, fhl.sk_partner) as ended_rentals_weekly,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',dc.dt_annulment), fhl.sk_region, fhl.sk_partner) as ended_rentals_monthly
from dim_contract dc
left join fact_listing_rent_flows rf
  using(sk_contract)
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
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('week',coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)), fhl.sk_region, fhl.sk_partner) as ended_rentals_confirmed_weekly,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)), fhl.sk_region, fhl.sk_partner) as ended_rentals_confirmed_monthly
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
new_bookers as (
	with
	first_booking as (
		select *
		from (
		    select
		    rf.ods_id,
		    rf.sk_client,
		    rf.sk_region,
		    date(db.dt_created) as first_booking_created_date,
		    row_number() over (partition by rf.sk_client order by db.dt_created asc) as rk
		    from fact_listing_rent_flows rf
		    join dim_booking db
		    	on db.sk_booking = rf.sk_booking
		    where rf.sk_booking_created_date
		)
		where rk = 1
		)
	select
	    fb.first_booking_created_date as first_booking_created_date,
	    fhl.sk_partner,
	    fb.sk_region,
	    count(distinct fb.sk_client) as new_bookers_daily
	from first_booking fb
	left join fact_listing_rent_flows rf
	  on (fb.sk_client = rf.sk_client)
	left join dim_date dd
	  on rf.sk_contract_signed_date = dd.sk_date
	left join dim_house_listing dhl
  	  on dhl.sk_house_listing = rf.sk_house_listing
  	left join fact_house_listings fhl
      on fhl.sk_house_listing = dhl.sk_house_listing
  	where dhl.is_b2b = True
	group by 1, 2, 3
),
ongoing_listings_daily as (
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
	)
	select
	    date,
	    sk_partner,
	    sk_region,
	    count(distinct sk_house_listing) as ongoing_listings_daily
	from daily_published_listings_adjusted
	group by 1,2,3
),
listing_to_contract_signed as (
with
sums as (
select
	date(dhl.ts_publication) as publication_date,
	fhl.sk_partner,
	dr.regional,
	dr.city_group,
    dr.city_name,
	count(distinct dhl.sk_house_listing) as total_listings,
	count(distinct fhl.sk_contract) as new_contracts_signed
from dim_house_listing dhl
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing
left join dim_region dr
  on dr.sk_region = fhl.sk_region
where dhl.ts_publication >= 0 and dhl.is_b2b = True
group by 1,2,3,4,5
)
select
	publication_date,
	sk_partner,
	regional,
	city_group,
	city_name,
	new_contracts_signed/total_listings::float as listing_to_contract_signed_daily
from sums
),
visits_booked_per_ongoing_listings as (
with
ongoing_listings as (
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
	  on d.sk_date between nullif(f.sk_status_start_date,-1) and coalesce(to_char(to_date(nullif(sk_status_end_date,-1),'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date -1, 'YYYYMMDD')::bigint)
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
	    dr.regional,
	    dr.city_group,
	    dr.city_name,
	    fhl.sk_partner
	from daily_published_listings fhs
	left join fact_house_listings fhl
	  on fhs.sk_house_listing = fhl.sk_house_listing
	left join dim_region dr
	  on fhl.sk_region = dr.sk_region
	where fhs.order_status = 1
	  and dr.city_group is not null
	)
	select
	    date,
	    sk_partner,
	    regional,
	    city_group,
	    city_name,
	    count(distinct sk_house_listing) as ongoing_listings
	from daily_published_listings_adjusted
	group by 1,2,3,4,5
),
visits_booked as (
    select
	dd.date,
	fhl.sk_partner,
	dr.regional,
	dr.city_group,
	dr.city_name,
	count(distinct case when (rf.sk_booking_created_date  > 0) then rf.sk_booking  else null end) as visits_booked
	from fact_listing_rent_flows rf
	join dim_booking db
		on db.sk_booking = rf.sk_booking
	join dim_date dd
		on dd.sk_date = rf.sk_booking_created_date
	left join dim_region dr
		on dr.sk_region = rf.sk_region
	left join dim_house_listing  dhl
		on dhl.sk_house_listing = rf.sk_house_listing
	left join fact_house_listings fhl
	  on rf.sk_house_listing = fhl.sk_house_listing
	where dr.city_group is not null and dhl.is_b2b = True
	group by 1, 2, 3, 4, 5
)
select
	vb.date,
	vb.sk_partner,
	vb.regional,
	vb.city_group,
	vb.city_name,
	vb.visits_booked/ol.ongoing_listings::float as vb_ol
from visits_booked vb
left join ongoing_listings ol
	on ol.date = vb.date and ol.city_name = vb.city_name and ol.sk_partner = vb.sk_partner
where vb.date is not null
),
daily_metrics as (
select
	distinct
	coalesce(ocont.date,orent.date,nrent.rental_date,ncont.contract_signed_date,nfl.first_listing_date,er.date_date, erc.date_date, rr.rental_date, olist.date, nbk.first_booking_created_date) as date_date,
	coalesce(ocont.sk_partner,orent.sk_partner,nrent.sk_partner,ncont.sk_partner,nfl.sk_partner, er.sk_partner,erc.sk_partner,rr.sk_partner, olist.sk_partner, nbk.sk_partner) as sk_partner,
	coalesce(ocont.sk_region,orent.sk_region,nrent.sk_region,ncont.sk_region,nfl.sk_region,er.sk_region, erc.sk_region, rr.sk_region, olist.sk_region, nbk.sk_region) as sk_region,
	ocont.ongoing_contracts_daily,
	orent.ongoing_rentals_daily,
	nrent.new_rentals_daily,
	ncont.new_contracts_signed_daily,
	nfl.new_first_listings_daily,
	rr.re_rentals_daily,
	er.ended_rentals_daily,
	erc.ended_rentals_confirmed_daily,
	olist.ongoing_listings_daily,
	nbk.new_bookers_daily
from ongoing_contracts_daily ocont
full outer join ongoing_rentals_daily orent
  on ocont.date = orent.date and ocont.sk_region = orent.sk_region and ocont.sk_partner = orent.sk_partner
full outer join new_rentals nrent
  on ocont.date = nrent.rental_date and ocont.sk_region = nrent.sk_region and ocont.sk_partner = nrent.sk_partner
full outer join new_contracts ncont
  on ocont.date = ncont.contract_signed_date and ocont.sk_region = ncont.sk_region and ocont.sk_partner = ncont.sk_partner
full outer join new_first_listings nfl
  on ocont.date = nfl.first_listing_date and ocont.sk_region = nfl.sk_region and ocont.sk_partner = nfl.sk_partner
full outer join re_rentals rr
  on ocont.date = rr.rental_date and ocont.sk_region = rr.sk_region and ocont.sk_partner = rr.sk_partner
full outer join ended_rentals er
  on ocont.date = er.date_date and ocont.sk_region = er.sk_region and ocont.sk_partner = er.sk_partner
full outer join ended_rentals_confirmed erc
  on ocont.date = erc.date_date and ocont.sk_region = erc.sk_region and ocont.sk_partner = erc.sk_partner
full outer join ongoing_listings_daily olist
  on ocont.date = olist.date and ocont.sk_region = olist.sk_region and ocont.sk_partner = olist.sk_partner
full outer join new_bookers nbk
  on ocont.date = nbk.first_booking_created_date and ocont.sk_region = nbk.sk_region and ocont.sk_partner = nbk.sk_partner
),
bookers as (
select
    dd.date as booking_created_date,
    fhl.sk_partner,
    dr.regional,
	dr.city_group,
	dr.city_name,
    count(distinct rf.sk_client) as bookers_daily
from fact_listing_rent_flows rf
inner join dim_date dd
  on rf.sk_booking_created_date = dd.sk_date
left join dim_house_listing dhl
  on dhl.sk_house_listing = rf.sk_house_listing
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing
left join dim_region dr
  on dr.sk_region = rf.sk_region
where dhl.is_b2b = True
group by 1, 2, 3, 4, 5
)
select
	coalesce(dm.date_date,b.booking_created_date,l2cs.publication_date,vb_ol.date) as date_date,
	coalesce(dm.sk_partner,b.sk_partner,l2cs.sk_partner,vb_ol.sk_partner) as sk_partner,
	coalesce(dr.regional,b.regional,l2cs.regional,vb_ol.regional) as regional,
	coalesce(dr.city_group,b.city_group,l2cs.city_group,vb_ol.city_group) as city_group,
	coalesce(dr.city_name,b.city_name,l2cs.city_name,vb_ol.city_name) as city_name,
	sum(dm.ongoing_contracts_daily) as ongoing_contracts_daily,
	sum(dm.ongoing_rentals_daily) as ongoing_rentals_daily,
	sum(dm.new_rentals_daily) as new_rentals,
	sum(dm.new_contracts_signed_daily) as new_contracts_signed,
	sum(dm.new_first_listings_daily) as new_first_listings,
	sum(dm.re_rentals_daily) as re_rentals,
	sum(dm.ended_rentals_daily) as ended_rentals,
	sum(dm.ended_rentals_confirmed_daily) as ended_rentals_confirmed_daily,
	sum(dm.ongoing_listings_daily) as ongoing_listings_daily,
	b.bookers_daily as bookers_daily,
	l2cs.listing_to_contract_signed_daily,
	vb_ol.vb_ol as visits_booked_per_ongoing_listings_daily,
	sum(dm.new_bookers_daily) as new_bookers_daily
from daily_metrics dm
left join dim_region dr
  using(sk_region)
full outer join bookers b
  on b.booking_created_date = dm.date_date and b.sk_partner = dm.sk_partner and b.city_name = dr.city_name
full outer join listing_to_contract_signed l2cs
  on l2cs.publication_date = dm.date_date and l2cs.sk_partner = dm.sk_partner and l2cs.city_name = dr.city_name
full outer join visits_booked_per_ongoing_listings vb_ol
  on vb_ol.date = dm.date_date and vb_ol.sk_partner = dm.sk_partner and vb_ol.city_name = dr.city_name
group by 1, 2, 3, 4, 5, 15, 16, 17;