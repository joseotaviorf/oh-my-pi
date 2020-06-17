with
rent_flows_temp as (
	with
	order_evalutaion as (
	select
	    *,
	    row_number() over(partition by proposal_id order by updated_at desc) as rn_last
	from datalake_docx_raw_prod.credit_evaluation
	where status <> 'PROCESSING'
	),
	evaluation_proposal as (
	select
	    proposal_id,
	    min(case when result in ('PRE_APPROVED','REGULAR') then updated_at end) as credit_evaluation_positive_first_date,
	    max(case when result in ('PRE_APPROVED','REGULAR') then updated_at end) as credit_evaluation_positive_last_date,
	    min(case when rn_last = 1 then result end) as result_last,
	    count(distinct id) as number_evaluations
	from order_evalutaion
	group by 1
	)
	select
	  rf.sk_house_listing,
	  rf.sk_region,
	  rf.sk_booking,
	  rf.sk_booking_created_date,
	  rf.sk_visit,
	  rf.sk_visit_date,
	  rf.flg_visit_completed,
	  case when (rf.sk_visit_date > 0 and rf.flg_visit_completed is true) then rf.sk_visit_date end as sk_visit_completed_date,
	  rf.sk_offer,
	  rf.sk_offer_submitted_date,
	  rf.sk_offer_approved_date,
	  rf.sk_proposal,
	  rf.sk_tenant_first_doc_sent_date,
	  coalesce(to_char(cast(ep.credit_evaluation_positive_first_date as timestamp), 'YYYYMMDD')::integer, -1) as sk_first_credit_evaluation_positive,
	  coalesce(to_char(cast(ep.credit_evaluation_positive_last_date as timestamp), 'YYYYMMDD')::integer, -1) as sk_last_credit_evaluation_positive,
	  ep.result_last as result_credit_evaluation,
	  rf.sk_first_credit_evaluation_init,
	  rf.sk_last_credit_evaluation_init,
	  rf.sk_first_credit_evaluation_negative,
	  rf.sk_last_credit_evaluation_negative,
	  rf.sk_first_doc_analysis_approved,
	  rf.sk_last_doc_analysis_approved,
	  rf.sk_last_doc_analysis_rejected,
	  ep.number_evaluations as number_credit_evaluations,
	  rf.sk_contract_created_date,
	  rf.sk_contract_signed_date,
	  rf.sk_contract
	from fact_listing_rent_flows rf
	left join evaluation_proposal ep
	  on rf.sk_proposal = ep.proposal_id
),
visits_booked as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  db.mkt_channel as demand_channel,
  count(distinct rf.sk_booking) as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_started,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_rejected,
  null::bigint as contract_created,
  null::bigint  as contract_signed
from dim_date dd
join rent_flows_temp rf
  on dd.sk_date = rf.sk_booking_created_date
  and rf.sk_booking_created_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_booking db
  on rf.sk_booking = db.sk_booking
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5
),
visits_completed as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  db.mkt_channel as demand_channel,
  null::bigint as visits_booked,
  count(distinct rf.sk_booking) as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_started,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_rejected,
  null::bigint as contract_created,
  null::bigint  as contract_signed
from dim_date dd
join rent_flows_temp rf
  on dd.sk_date = rf.sk_visit_date
  and rf.sk_visit_date > 0 and rf.flg_visit_completed = 1
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_booking db
  on rf.sk_booking = db.sk_booking
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5
),
offer_submitted as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  dof.mkt_medium as demand_channel,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  count(distinct rf.sk_offer) as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_started,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_rejected,
  null::bigint as contract_created,
  null::bigint  as contract_signed
from dim_date dd
join rent_flows_temp rf
  on dd.sk_date = rf.sk_offer_submitted_date
  and rf.sk_offer_submitted_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date"between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5
),
offer_approved as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  dof.mkt_medium as demand_channel,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  count(distinct rf.sk_offer) as offer_approved,
  null::bigint as credit_evaluation_started,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_rejected,
  null::bigint as contract_created,
  null::bigint  as contract_signed
from dim_date dd
join rent_flows_temp rf
  on dd.sk_date = rf.sk_offer_approved_date
  and rf.sk_offer_approved_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5
),
credit_evaluation_started as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  dof.mkt_medium as demand_channel,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  count(distinct rf.sk_offer) as credit_evaluation_started,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_rejected,
  null::bigint as contract_created,
  null::bigint  as contract_signed
from dim_date dd
join rent_flows_temp rf
  on dd.sk_date = rf.sk_first_credit_evaluation_init
  and rf.sk_first_credit_evaluation_init > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5
),
credit_evaluation_positive as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  dof.mkt_medium as demand_channel,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_started,
  count(distinct rf.sk_offer) as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_rejected,
  null::bigint as contract_created,
  null::bigint  as contract_signed
from dim_date dd
join rent_flows_temp rf
  on dd.sk_date = rf.sk_last_credit_evaluation_positive
  and rf.sk_last_credit_evaluation_positive > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5
),
doc_sent as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  dof.mkt_medium as demand_channel,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_started,
  null::bigint as credit_evaluation_positive,
  count(distinct rf.sk_offer) as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_rejected,
  null::bigint as contract_created,
  null::bigint  as contract_signed
from dim_date dd
join rent_flows_temp rf
  on dd.sk_date = rf.sk_tenant_first_doc_sent_date
  and rf.sk_tenant_first_doc_sent_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5
),
doc_approved as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  dof.mkt_medium as demand_channel,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_started,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  count(distinct rf.sk_offer) as doc_approved,
  null::bigint as doc_rejected,
  null::bigint as contract_created,
  null::bigint as contract_signed
from dim_date dd
join rent_flows_temp rf
  on dd.sk_date = rf.sk_last_doc_analysis_approved
  and rf.sk_last_doc_analysis_approved > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5
),
doc_rejected as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  dof.mkt_medium as demand_channel,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_started,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  count(distinct rf.sk_offer) as doc_rejected,
  null::bigint as contract_created,
  null::bigint as contract_signed
from dim_date dd
join rent_flows_temp rf
  on dd.sk_date = rf.sk_last_doc_analysis_rejected
  and rf.sk_last_doc_analysis_rejected > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5
),
contract_created as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  dof.mkt_medium as demand_channel,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_started,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_rejected,
  count(distinct rf.sk_contract) as contract_created,
  null::bigint as contract_signed
from dim_date dd
join rent_flows_temp rf
  on dd.sk_date = rf.sk_contract_created_date
  and rf.sk_contract_created_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5
),
contract_signed as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  dof.mkt_medium as demand_channel,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_started,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_rejected,
  null::bigint as contract_created,
  count(distinct rf.sk_contract) as contract_signed
from dim_date dd
join rent_flows_temp rf
  on dd.sk_date = rf.sk_contract_signed_date
  and rf.sk_contract_signed_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5
),
union_all as (
	select * from visits_booked
	union all
	select * from visits_completed
	union all
	select * from offer_submitted
	union all
	select * from offer_approved
	union all
	select * from credit_evaluation_started
	union all
	select * from credit_evaluation_positive
	union all
	select * from doc_sent
	union all
	select * from doc_approved
	union all
    select * from doc_rejected
	union all
	select * from contract_created
	union all
	select * from contract_signed
),
union_all_date as (
select
	dd."date",
	ua.city_group,
  ua.is_b2b,
  ua.demand_channel,
  ua.visits_booked,
  ua.visits_completed,
  ua.offer_submitted,
  ua.offer_approved,
  ua.credit_evaluation_started,
  ua.credit_evaluation_positive,
  ua.doc_sent,
  ua.doc_approved,
  ua.doc_rejected,
  ua.contract_created,
  ua.contract_signed
from union_all ua
right join dim_date dd
  on ua.sk_date = dd.sk_date
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date
)
select
	"date",
	city_group,
    case when demand_channel in ('Not Mapped', 'Other') or demand_channel is null then 'Other'
         else demand_channel end as demand_channel,
  is_b2b as is_b2b_demand,
  sum(visits_booked) as visits_booked,
  sum(visits_completed) as visits_completed,
  sum(offer_submitted) as offer_submitted,
  sum(offer_approved) as offer_approved,
  sum(credit_evaluation_started) as credit_evaluation_started,
  sum(credit_evaluation_positive) as credit_evaluation_positive,
  sum(doc_sent) as doc_sent,
  sum(doc_approved) as doc_approved,
  sum(doc_rejected) as doc_rejected,
  sum(contract_created) as contract_created,
  sum(contract_signed) as contract_signed,
  current_timestamp as ts_load	
from union_all
group by "date", city_group, 3, 4
