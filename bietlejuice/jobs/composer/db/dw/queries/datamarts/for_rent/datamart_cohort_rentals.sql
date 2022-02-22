-- Query to collect rentals, re-rentals, ended_re_rentals, rent value and admin fee in the first rental cohort

with
all_listings as (
select
	rf.sk_house_listing,
	dhl.id_house,
	rf.sk_contract,
	dhl.ts_publication,
	dhl.listing_category_start,
	rf.days_house_listing_to_contract_signed,
	dc.ts_signature,
	coalesce(date(replace(replace(replace(dc.dt_start,'0019','2019'),'2009','2019'),'0020','2020')), dc.dt_entrance) as dt_start,
	dc.dt_annulment,
	dc.status,
	dc.rent as value_rent,
	dc.first_rental_commission,
	cfull.taxaadministracaomensal as admin_fee,
	dr.city_group,
	dr.city_name,
	row_number() over (partition by dhl.id_house order by dc.dt_start) as order_contracts,
	row_number() over (partition by dhl.id_house, rf.sk_contract order by dc.dt_start) as dupli_contracts,
	lead(dhl.ts_publication, 1) over (partition by dhl.id_house order by rf.sk_house_listing) as next_listing,
	lead(dc.dt_start, 1) over (partition by dhl.id_house order by rf.sk_house_listing) as next_contract,
	count(rf.sk_house_listing) over (partition by dhl.id_house) as total_listings,
	min(dc.dt_start) over (partition by dhl.id_house) as first_dt_start
from dim_contract dc
left join fact_listing_rent_flows rf
  on dc.sk_contract = rf.sk_contract and (rf.sk_contract_signed_date > 0 or rf.sk_contract_created_date > 0)
left join dim_house_listing dhl -- bring information about the listing
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_region dr -- bring information from city_group
  on rf.sk_region = dr.sk_region
left join datalake_ebdb_raw_prod.contratofull cfull -- bring administration fee
  on cfull.id = dc.sk_contract
where dc.status in ('Ativo','Finalizado') -- consider only active or ended contracts
  and (dc.dt_start <= dc.dt_annulment or dc.dt_annulment is null) --Ignore contracts that have dt_anullment before dt_start
),
all_first_contracts as (
select
	city_group,
	city_name,
	date_trunc('month', dt_start) as contract_start_month,
	dt_start,
	date_trunc('month',dt_annulment) as contract_end_month,
	dt_annulment,
	dd.date,
	dd.month_start,
	sk_house_listing,
	sk_contract,
	id_house,
	value_rent,
	admin_fee
from all_listings al
join dim_date dd
  on dd.date between al.dt_start and coalesce(dt_annulment, dateadd('day',-1,current_date))
where order_contracts = 1 and sk_contract > 0 and dupli_contracts = 1 and dd.date <= current_date
order by 1 desc
),
all_next_contracts as (
select
	city_group,
	city_name,
	date_trunc('month', first_dt_start) as contract_first_start_month,
	first_dt_start,
	date_trunc('month', dt_start) as contract_start_month,
	dt_start,
	date_trunc('month',dt_annulment) as contract_end_month,
	dt_annulment,
	dd.date,
	dd.month_start,
	sk_house_listing,
	id_house,
	value_rent,
	admin_fee
from all_listings al
join dim_date dd
  on dd.date between al.dt_start and coalesce(al.dt_annulment, dateadd('day',-1,current_date))
where order_contracts > 1 and sk_contract > 0 and dupli_contracts = 1 and dd.date <= current_date
order by 1 desc
),
all_first_rentals as (
select
	city_group,
	to_char(contract_start_month,'YYYY-MM-DD') as contract_start_month,
	datediff('month',contract_start_month,month_start) as months_after_first_contract,
	count(distinct id_house) as total_first_rentals
from all_first_contracts
group by 1, 2, 3
),
all_re_rentals as (
select
	city_group,
	to_char(contract_first_start_month,'YYYY-MM-DD') as contract_start_month,
	datediff('month',contract_first_start_month,month_start) as months_after_first_contract,
	count(distinct id_house) as total_re_rentals
from all_next_contracts
group by 1, 2, 3
),
all_ended_re_rentals as (
select
    city_group,
	to_char(anc.contract_first_start_month,'YYYY-MM-DD') as contract_start_month,
	datediff('month',anc.contract_first_start_month,anc.contract_end_month) as months_between_first_contract_and_ended,
	count(distinct anc.id_house) as total_ended_re_rentals
from all_next_contracts anc
where anc.contract_end_month is not null
group by 1, 2, 3
),
all_first_contract_rent as (
select
	city_group,
    contract_start_month,
    months_after_first_contract,
    avg(value_rent) as avg_value_rent_first_rentals
from (
select
    distinct
    city_group,
	to_char(contract_start_month,'YYYY-MM-DD') as contract_start_month,
	datediff('month',contract_start_month,month_start) as months_after_first_contract,
    id_house,
    value_rent
from all_first_contracts
)
group by 1, 2, 3
),
all_re_rental_rent as (
select
	city_group,
    contract_start_month,
    months_after_first_contract,
    avg(value_rent) as avg_value_rent_re_rentals
from (
select
    distinct
    city_group,
	to_char(contract_first_start_month,'YYYY-MM-DD') as contract_start_month,
	datediff('month',contract_first_start_month,month_start) as months_after_first_contract,
    id_house,
    value_rent
from all_next_contracts
)
group by 1, 2, 3
),
all_first_contract_adm_fee as (
select
	city_group,
    contract_start_month,
    months_after_first_contract,
    avg(admin_fee) as avg_admin_fee_first_rentals
from (
select
    distinct
    city_group,
	to_char(contract_start_month,'YYYY-MM-DD') as contract_start_month,
	datediff('month',contract_start_month,month_start) as months_after_first_contract,
    id_house,
    admin_fee
from all_first_contracts
)
group by 1, 2, 3
),
all_re_rental_adm_fee as (
select
	city_group,
    contract_start_month,
    months_after_first_contract,
    avg(admin_fee) as avg_admin_fee_re_rentals
from (
select
    distinct
    city_group,
	to_char(contract_first_start_month,'YYYY-MM-DD') as contract_start_month,
	datediff('month',contract_first_start_month,month_start) as months_after_first_contract,
    id_house,
    admin_fee
from all_next_contracts
)
group by 1, 2, 3
)
select
    fr.city_group,
	fr.contract_start_month,
	fr.months_after_first_contract,
	fr.total_first_rentals,
	rr.total_re_rentals,
	err.total_ended_re_rentals,
	fcr.avg_value_rent_first_rentals,
	fcaf.avg_admin_fee_first_rentals,
	rr_rent.avg_value_rent_re_rentals,
	rr_af.avg_admin_fee_re_rentals,
	current_timestamp as ts_load
from all_first_rentals fr
left join all_re_rentals rr
  on fr.city_group = rr.city_group
  and fr.contract_start_month = rr.contract_start_month
  and fr.months_after_first_contract = rr.months_after_first_contract
left join all_ended_re_rentals err
  on fr.city_group = err.city_group
  and fr.contract_start_month = err.contract_start_month
  and fr.months_after_first_contract = err.months_between_first_contract_and_ended
left join all_first_contract_rent fcr
  on fr.city_group = fcr.city_group
  and fr.contract_start_month = fcr.contract_start_month
  and fr.months_after_first_contract = fcr.months_after_first_contract
left join all_first_contract_adm_fee fcaf
  on fr.city_group = fcaf.city_group
  and fr.contract_start_month = fcaf.contract_start_month
  and fr.months_after_first_contract = fcaf.months_after_first_contract
left join all_re_rental_rent rr_rent
  on fr.city_group = rr_rent.city_group
  and fr.contract_start_month = rr_rent.contract_start_month
  and fr.months_after_first_contract = rr_rent.months_after_first_contract
left join all_re_rental_adm_fee rr_af
  on fr.city_group = rr_af.city_group
  and fr.contract_start_month = rr_af.contract_start_month
  and fr.months_after_first_contract = rr_af.months_after_first_contract
order by 1, 2 desc, 3