with visits_booked as (
	select
		  dd."date",
		  dd.sk_date,
		  rf.sk_client,
		  rf.sk_house_listing,
		  count(distinct sk_booking) as visits_booked,
 	   	  0 as visits_completed,
		  0 as offer_submitted,
		  0 as offer_approved,
		  0 as doc_sent,
		  0 as doc_completed,
		  0 as credit_processed,
		  0 as credit_approved,
		  0 as contract_created,
		  0 as contract_signed,
		  0 as contract_ended
	from dim_date dd
	join fact_listing_rent_flows rf
	  	on dd.sk_date = rf.sk_booking_created_date
	  		and rf.sk_booking_created_date > 0
	where dd."date" > date('2019-09-30')
	group by 1,2,3,4
),
visits_completed as (
	select
		  dd."date",
		  dd.sk_date,
		  rf.sk_client,
		  rf.sk_house_listing,
		  0 as visits_booked,
 	   	  count(distinct rf.sk_booking) as visits_completed,
		  0 as offer_submitted,
		  0 as offer_approved,
		  0 as doc_sent,
		  0 as doc_completed,
		  0 as credit_processed,
		  0 as credit_approved,
		  0 as contract_created,
		  0 as contract_signed,
		  0 as contract_ended
	from dim_date dd
	join fact_listing_rent_flows rf
	  	on dd.sk_date = rf.sk_visit_date
	  		and rf.sk_visit_date > 0 and rf.flg_visit_completed = 1
	where dd."date" > date('2019-09-30')
	group by 1,2,3,4
),
offer_submitted as (
	select
		  dd."date",
		  dd.sk_date,
		  rf.sk_client,
		  rf.sk_house_listing,
		  0 as visits_booked,
 	   	  0 as visits_completed,
		  count(distinct rf.sk_offer) as offer_submitted,
		  0 as offer_approved,
		  0 as doc_sent,
		  0 as doc_completed,
		  0 as credit_processed,
		  0 as credit_approved,
		  0 as contract_created,
		  0 as contract_signed,
		  0 as contract_ended
	from dim_date dd
	join fact_listing_rent_flows rf
	  	on dd.sk_date = rf.sk_offer_submitted_date
	  		and rf.sk_offer_submitted_date > 0
	where dd."date" > date('2019-09-30')
	group by 1,2,3,4
),
offer_approved as (
	select
		  dd."date",
		  dd.sk_date,
		  rf.sk_client,
		  rf.sk_house_listing,
		  0 as visits_booked,
 	   	  0 as visits_completed,
		  0 as offer_submitted,
		  count(distinct rf.sk_offer) as offer_approved,
		  0 as doc_sent,
		  0 as doc_completed,
		  0 as credit_processed,
		  0 as credit_approved,
		  0 as contract_created,
		  0 as contract_signed,
		  0 as contract_ended
	from dim_date dd
	join fact_listing_rent_flows rf
	  on dd.sk_date = rf.sk_offer_approved_date
	  and rf.sk_offer_approved_date > 0
	where dd."date" > date('2019-09-30')
	group by 1,2,3,4
),
doc_sent as (
	select
		  dd."date",
		  dd.sk_date,
		  rf.sk_client,
		  rf.sk_house_listing,
		  0 as visits_booked,
 	   	  0 as visits_completed,
		  0 as offer_submitted,
		  0 as offer_approved,
		  count(distinct rf.sk_offer) as doc_sent,
		  0 as doc_completed,
		  0 as credit_processed,
		  0 as credit_approved,
		  0 as contract_created,
		  0 as contract_signed,
		  0 as contract_ended
	from dim_date dd
	join fact_listing_rent_flows rf
	  on dd.sk_date = rf.sk_tenant_first_doc_sent_date
	  and rf.sk_tenant_first_doc_sent_date > 0
	where dd."date" > date('2019-09-30')
	group by 1,2,3,4
),
doc_completed as (
	select
		  dd."date",
		  dd.sk_date,
		  rf.sk_client,
		  rf.sk_house_listing,
		  0 as visits_booked,
 	   	  0 as visits_completed,
		  0 as offer_submitted,
		  0 as offer_approved,
		  0 as doc_sent,
		  count(distinct rf.sk_offer) as doc_completed,
		  0 as credit_processed,
		  0 as credit_approved,
		  0 as contract_created,
		  0 as contract_signed,
		  0 as contract_ended
	from dim_date dd
	join fact_listing_rent_flows rf
	  on dd.sk_date = rf.sk_credit_analysis_init_date
	  and rf.sk_credit_analysis_init_date > 0
	where dd."date" > date('2019-09-30')
	group by 1,2,3,4
),
credit_processed as (
	select
		  dd."date",
		  dd.sk_date,
		  rf.sk_client,
		  rf.sk_house_listing,
		  0 as visits_booked,
 	   	  0 as visits_completed,
		  0 as offer_submitted,
		  0 as offer_approved,
		  0 as doc_sent,
		  0 as doc_completed,
		  count(distinct rf.sk_offer) as credit_processed,
		  0 as credit_approved,
		  0 as contract_created,
		  0 as contract_signed,
		  0 as contract_ended
	from dim_date dd
	join fact_listing_rent_flows rf
	  on dd.sk_date = rf.sk_credit_analysis_end_date
	  and rf.sk_credit_analysis_end_date > 0
	where dd."date" > date('2019-09-30')
	group by 1,2,3,4
),
credit_approved as (
	select
		  dd."date",
		  dd.sk_date,
		  rf.sk_client,
		  rf.sk_house_listing,
		  0 as visits_booked,
 	   	  0 as visits_completed,
		  0 as offer_submitted,
		  0 as offer_approved,
		  0 as doc_sent,
		  0 as doc_completed,
		  0 as credit_processed,
		  count(distinct rf.sk_offer) as credit_approved,
		  0 as contract_created,
		  0 as contract_signed,
		  0 as contract_ended
	from dim_date dd
	join fact_listing_rent_flows rf
	  on dd.sk_date = rf.sk_credit_analysis_approved_date
	  and rf.sk_credit_analysis_approved_date > 0
	where dd."date" > date('2019-09-30')
	group by 1,2,3,4
),
contract_created as (
	select
		  dd."date",
		  dd.sk_date,
		  rf.sk_client,
		  rf.sk_house_listing,
		  0 as visits_booked,
 	   	  0 as visits_completed,
		  0 as offer_submitted,
		  0 as offer_approved,
		  0 as doc_sent,
		  0 as doc_completed,
		  0 as credit_processed,
		  0 as credit_approved,
		  count(distinct rf.sk_contract) as contract_created,
		  0 as contract_signed,
		  0 as contract_ended
	from dim_date dd
	join fact_listing_rent_flows rf
	  on dd.sk_date = rf.sk_contract_created_date
	  and rf.sk_contract_created_date > 0
	where dd."date" > date('2019-09-30')
	group by 1,2,3,4
),
contract_signed as (
	select
		  dd."date",
		  dd.sk_date,
		  rf.sk_client,
		  rf.sk_house_listing,
		  0 as visits_booked,
 	   	  0 as visits_completed,
		  0 as offer_submitted,
		  0 as offer_approved,
		  0 as doc_sent,
		  0 as doc_completed,
		  0 as credit_processed,
		  0 as credit_approved,
		  0 as contract_created,
		  count(distinct rf.sk_contract) as contract_signed,
		  0 as contract_ended
	from dim_date dd
	join fact_listing_rent_flows rf
	  on dd.sk_date = rf.sk_contract_signed_date
	  and rf.sk_contract_signed_date > 0
	where dd."date" > date('2019-09-30')
	group by 1,2,3,4
),
contract_ended as (
	select
		  dd."date",
		  dd.sk_date,
		  rf.sk_client,
		  rf.sk_house_listing,
		  0 as visits_booked,
 	   	  0 as visits_completed,
		  0 as offer_submitted,
		  0 as offer_approved,
		  0 as doc_sent,
		  0 as doc_completed,
		  0 as credit_processed,
		  0 as credit_approved,
		  0 as contract_created,
		  0 as contract_signed,
		  count(distinct rf.sk_contract) as contract_ended
	from dim_date dd
	join fact_listing_rent_flows rf
	  on dd.sk_date = rf.sk_contract_annulment_date
	  and rf.sk_contract_signed_date > 0 and rf.sk_contract_annulment_date > 0
	where dd."date" > date('2019-09-30')
	group by 1,2,3,4
),
union_demand_metrics as (
	select
		*
	from visits_booked
		union all
	select
		*
	from visits_completed
		union all
	select
		*
	from offer_submitted
		union all
	select
		*
	from offer_approved
		union all
	select
		*
	from doc_sent
			union all
	select
		*
	from doc_completed
			union all
	select
		*
	from credit_processed
			union all
	select
		*
	from credit_approved
			union all
	select
		*
	from contract_created
		union all
	select
		*
	from contract_signed
			union all
	select
		*
	from contract_ended
),
base_demand as (
	select
		  date,
		  sk_date,
		  sk_client,
		  sk_house_listing,
		  sum(visits_booked) as visits_booked,
		  sum(visits_completed) as visits_completed,
		  sum(offer_submitted) as offer_submitted,
		  sum(offer_approved) as offer_approved,
		  sum(doc_sent) as doc_sent,
		  sum(doc_completed) as doc_completed,
		  sum(credit_processed) as credit_processed,
		  sum(credit_approved) as credit_approved,
		  sum(contract_created) as contract_created,
		  sum(contract_signed) as contract_signed,
		  sum(contract_ended) as contract_ended
	from union_demand_metrics
	group by 1,2,3,4
),
house_status as (
	select
		  fhs.sk_house_listing,
		  fhs.sk_region,
		  fhs.status_history as status,
		  min(fhs.sk_status_start_date) as sk_min_status_date,
		  coalesce(to_char(to_date(case when fhs.sk_status_end_date>-1 then fhs.sk_status_end_date else null end, 'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date - 1, 'YYYYMMDD')::bigint) as sk_max_status_date
	from fact_house_listing_status fhs
	where sk_house_listing%1000 <> 0
	group by 1,2,3,5
),
house_status_per_day as (
	select
		  hsp.sk_house_listing,
		  hsp.sk_region,
		  hsp.status,
		  hsp.sk_min_status_date,
		  hsp.sk_max_status_date,
		  dd.date,
		  dd.sk_date,
		  dd.week_day,
		  dd.week_start
	from house_status hsp
	join dim_date dd
		on dd.sk_date between hsp.sk_min_status_date and sk_max_status_date
	where dd."date" > date('2019-09-30')
),
published_listings as (
	select
		  hsd.date,
		  hsd.sk_date,
		  NULL::integer as sk_client,
		  hsd.sk_house_listing,
		  0 as visits_booked,
		  0 as visits_completed,
		  0 as offer_submitted,
		  0 as offer_approved,
		  0 as doc_sent,
		  0 as doc_completed,
		  0 as credit_processed,
		  0 as credit_approved,
		  0 as contract_created,
		  0 as contract_signed,
		  0 as contract_ended
	from house_status_per_day hsd
	where status = 'publicado'
),
published_listings_no_demand as (
	select
		  pl.date,
		  pl.sk_date,
		  pl.sk_client,
		  pl.sk_house_listing,
		  pl.visits_booked,
		  pl.visits_completed,
		  pl.offer_submitted,
		  pl.offer_approved,
		  pl.doc_sent,
		  pl.doc_completed,
		  pl.credit_processed,
		  pl.credit_approved,
		  pl.contract_created,
		  pl.contract_signed,
		  pl.contract_ended
	from published_listings pl
		left join (select distinct sk_date, sk_house_listing from base_demand) bd
				on pl.sk_date = bd.sk_date and pl.sk_house_listing = bd.sk_house_listing
	where bd.sk_house_listing is null
),
demand_union_published as (
	select
		*
	from base_demand
		union all
	select
		*
	from published_listings_no_demand
),
total as (
	select
		t.date,
		t.sk_client,
		t.sk_house_listing,
		hs.status as listing_status,
		t.visits_booked,
		t.visits_completed,
		t.offer_submitted,
		t.offer_approved,
		t.doc_sent,
		t.doc_completed,
		t.credit_processed,
		t.credit_approved,
		t.contract_created,
		t.contract_signed,
		t.contract_ended
	from demand_union_published t
		left join house_status_per_day hs
			on t.sk_house_listing = hs.sk_house_listing and t.date = hs.date
),
union_total as (
select
	*
from total
union all
select
	cast(aldh.date as date),
	cast(aldh.sk_client as bigint),
	cast(aldh.sk_house_listing as bigint),
	cast(aldh.listing_status as varchar),
	cast(aldh.visits_booked as bigint),
	cast(aldh.visits_completed as bigint),
	cast(aldh.offer_submitted as bigint),
	cast(aldh.offer_approved as bigint),
	cast(aldh.doc_sent as bigint),
	cast(aldh.doc_completed as bigint),
	cast(aldh.credit_processed as bigint),
	cast(aldh.credit_approved as bigint),
	cast(aldh.contract_created as bigint),
	cast(aldh.contract_signed as bigint),
	cast(aldh.contract_ended as bigint)
from datalake_raw.datamart_available_listings_users_demand_historic aldh
order by 1,3
)
select
	*,
	current_timestamp as ts_load
from union_total
