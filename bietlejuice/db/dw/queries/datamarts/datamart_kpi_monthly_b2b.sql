with
ongoing_contracts_monthly as (
select
  dd.month_start,
  fhl.sk_partner,
  fhl.sk_region,
  count(distinct dc.sk_contract) as ongoing_contracts_monthly
from dim_contract dc
join dim_date dd
  on dd.date between date(coalesce(coalesce(dc.ts_signature,dc.dt_start),dc.dt_entrance)) and (coalesce(dc.dt_annulment, CURRENT_DATE) - 1)
left join fact_house_listings fhl
  on fhl.sk_contract = dc.sk_contract
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhl.sk_house_listing
where (dc.dt_annulment < current_date OR dc.dt_annulment is null) -- we know we may have future dates for dt_annulment
  and dc.status in ('Ativo','Finalizado') -- consider only contracts that are active or were active and ended
  and dd.date = dd.month_end
  and dhl.is_b2b = True
  and type <> 'DealOnly' -- this type of contract should only be considered for new contracts signed
group by 1, 2, 3
),
ongoing_rentals_monthly as (
select
	  dd.month_start,
	  fhl.sk_partner,
	  fhl.sk_region,
	  count(distinct dc.sk_contract) as ongoing_rentals_monthly
from dim_contract dc
join dim_date dd
  on dd.date between date(coalesce(dc.dt_start, dc.dt_entrance)) and (coalesce(dc.dt_annulment, current_date) - interval '1 day')
left join fact_house_listings fhl
  on fhl.sk_contract = dc.sk_contract
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhl.sk_house_listing
where dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
  and dd.date = dd.month_end -- only look last day of the month
  and date(coalesce(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
  and (dc.dt_annulment < current_date OR dc.dt_annulment is null) -- we know we may have future dates for dt_annulment
  and type <> 'DealOnly'
  and dhl.is_b2b = True
group by 1, 2, 3
),
new_rentals as (
select
	date_trunc('month',coalesce(dc.dt_start, dc.dt_entrance)) as rental_month_start,
	fhl.sk_partner,
	fhl.sk_region,
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
group by 1, 2, 3
),
new_contracts as (
select
  date_trunc('month',coalesce(dc.ts_signature, dc.dt_start)) as contract_month_start,
  fhl.sk_partner,
  fhl.sk_region,
  sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',coalesce(dc.ts_signature, dc.dt_start)), fhl.sk_region, fhl.sk_partner) as new_contracts_signed_monthly
from dim_contract dc
left join fact_house_listings fhl
  on fhl.sk_contract = dc.sk_contract
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhl.sk_house_listing
  where dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active and ended
  and dhl.is_b2b = True
group by 1, 2, 3
),
new_first_listings as (
select
    date_trunc('month', dd.date) as first_listing_month_start,
    fhl.sk_partner,
    lf.sk_region,
    sum(count(distinct lf.sk_house_listing)) over(partition by date_trunc('month',dd.date), lf.sk_region, fhl.sk_partner) as new_first_listings_monthly
from public.fact_house_listing_flows lf
join dim_date dd
  on lf.sk_first_listing_date = dd.sk_date
left join dim_house_listing dhl
  on dhl.sk_house_listing = lf.sk_house_listing
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing
  and dd.date < current_date
  where lf.sk_first_listing_date > 0
  and dhl.is_b2b = True
group by 1, 2, 3
),
re_rentals as (
	with ordered_rentals as (
		select
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
		ord.rental_month_start,
		ord.sk_partner,
		ord.sk_region,
		sum(count(distinct ord.sk_contract)) over(partition by date_trunc('month',ord.rental_month_start), ord.sk_region, ord.sk_partner) as re_rentals_monthly
	from ordered_rentals ord
	where ord.row_number_renting > 1 and ord.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
	group by 1, 2, 3
),
ended_rentals as (
select
	date_trunc('month',dc.dt_annulment) as month_date,
	fhl.sk_partner,
	fhl.sk_region,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',dc.dt_annulment), fhl.sk_region, fhl.sk_partner) as ended_rentals_monthly
from dim_contract dc
left join fact_house_listings fhl
  on fhl.sk_contract = dc.sk_contract
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhl.sk_house_listing
where dc.status = 'Finalizado'
      and dc.dt_annulment < current_date
      and dhl.is_b2b = True
group by 1, 2, 3
),
bookers as (
select
    date_trunc('month',dd.date) as booking_created_month,
    fhl.sk_partner,
    rf.sk_region,
    count(distinct rf.sk_client) as bookers_monthly
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
ended_rentals_confirmed as (
select
	date_trunc('month',coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)) as month_date,
	fhl.sk_partner,
	fhl.sk_region,
	sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)), fhl.sk_region, fhl.sk_partner) as ended_rentals_confirmed_monthly
from dim_contract dc
left join fact_house_listings fhl
  on fhl.sk_contract = dc.sk_contract
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhl.sk_house_listing
where dc.status = 'Finalizado'
	  and dhl.is_b2b = True
      and coalesce(ts_analyst_annulment_input,dc.dt_annulment) < current_date
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
	    date_trunc('month',fb.first_booking_created_date) as first_booking_created_month,
	    fhl.sk_partner,
	    fb.sk_region,
	    count(distinct fb.sk_client) as new_bookers_monthly
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
ongoing_listings_monthly as (
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
  and fhs.date = fhs.month_end -- filter that indicates it will be grouped by month
)
select
    month_start,
    sk_partner,
    sk_region,
    count(distinct sk_house_listing) as ongoing_listings_monthly
from daily_published_listings_adjusted
group by 1, 2, 3
),
monthly_metrics as (
select
	distinct coalesce(ocont.month_start,orent.month_start,nrent.rental_month_start,ncont.contract_month_start,nfl.first_listing_month_start,er.month_date,erc.month_date,rr.rental_month_start,olist.month_start,bk.booking_created_month,nbk.first_booking_created_month) as month_date,
	coalesce(ocont.sk_region,orent.sk_region,nrent.sk_region,ncont.sk_region,nfl.sk_region, er.sk_region,erc.sk_region,rr.sk_region, olist.sk_region, bk.sk_region, nbk.sk_region) as sk_region,
	coalesce(ocont.sk_partner,orent.sk_partner,nrent.sk_partner,ncont.sk_partner,nfl.sk_partner, er.sk_partner,erc.sk_partner,rr.sk_partner, olist.sk_partner, bk.sk_partner, nbk.sk_partner) as sk_partner,
	ocont.ongoing_contracts_monthly,
	orent.ongoing_rentals_monthly,
	nrent.new_rentals_monthly,
	ncont.new_contracts_signed_monthly,
	rr.re_rentals_monthly,
	nfl.new_first_listings_monthly,
	er.ended_rentals_monthly,
	erc.ended_rentals_confirmed_monthly,
	olist.ongoing_listings_monthly,
	bk.bookers_monthly,
	nbk.new_bookers_monthly
from ongoing_contracts_monthly ocont
full outer join ongoing_rentals_monthly orent
  on ocont.month_start = orent.month_start and ocont.sk_region = orent.sk_region and ocont.sk_partner = orent.sk_partner
full outer join new_rentals nrent
  on ocont.month_start = nrent.rental_month_start and ocont.sk_region = nrent.sk_region and ocont.sk_partner = nrent.sk_partner
full outer join new_contracts ncont
  on ocont.month_start = ncont.contract_month_start and ocont.sk_region = ncont.sk_region and ocont.sk_partner = ncont.sk_partner
full outer join re_rentals rr
  on rr.rental_month_start = ocont.month_start and rr.sk_region = ocont.sk_region and rr.sk_partner = ocont.sk_partner
full outer join new_first_listings nfl
  on ocont.month_start = nfl.first_listing_month_start and ocont.sk_region = nfl.sk_region and ocont.sk_partner = nfl.sk_partner
full outer join ended_rentals er
  on ocont.month_start = er.month_date and ocont.sk_region = er.sk_region and ocont.sk_partner = er.sk_partner
full outer join ended_rentals_confirmed erc
  on ocont.month_start = erc.month_date and ocont.sk_region = erc.sk_region and ocont.sk_partner = erc.sk_partner
full outer join ongoing_listings_monthly olist
  on ocont.month_start = olist.month_start and ocont.sk_region = olist.sk_region and ocont.sk_partner = olist.sk_partner
full outer join bookers bk
  on ocont.month_start = bk.booking_created_month and ocont.sk_region = bk.sk_region and ocont.sk_partner = bk.sk_partner
full outer join new_bookers nbk
  on ocont.month_start = nbk.first_booking_created_month and ocont.sk_region = nbk.sk_region and ocont.sk_partner = nbk.sk_partner
)
select
	dm.month_date,
	dm.sk_partner,
	dr.regional,
	dr.city_group,
	dr.city_name,
	sum(dm.ongoing_contracts_monthly) as ongoing_contracts_monthly,
	sum(dm.ongoing_rentals_monthly) as ongoing_rentals_monthly,
	sum(dm.new_rentals_monthly) as new_rentals_monthly,
	sum(dm.new_contracts_signed_monthly) as new_contracts_signed_monthly,
	sum(dm.new_first_listings_monthly) as new_first_listings_monthly,
	sum(dm.re_rentals_monthly) as re_rentals_monthly,
	sum(dm.ended_rentals_monthly) as ended_rentals_monthly,
	sum(dm.ended_rentals_confirmed_monthly) as ended_rentals_confirmed_monthly,
	sum(dm.ongoing_listings_monthly) as ongoing_listings_monthly,
	sum(dm.bookers_monthly) as bookers_monthly,
	sum(dm.new_bookers_monthly) as new_bookers_monthly
from monthly_metrics dm
left join dim_region dr
  using(sk_region)
group by 1, 2, 3, 4, 5;
