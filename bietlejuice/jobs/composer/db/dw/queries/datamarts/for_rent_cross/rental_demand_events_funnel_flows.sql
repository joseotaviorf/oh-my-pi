with
rent_flows_adap as (
-- adpating rent_flows output so we can add tta events and the category of each flow
	with
	tta_complete as (
	select
		sk_house_listing,
		tenant_id as sk_client,
		agent_id,
		region_code,
		date(first_message_ts) as first_message_date,
		date(first_attendance_ts) as first_attendance_date
	from datamarts.talk_to_agent
	)
	select
	    rf.sk_rent_flow,
	    rf.sk_house_listing,
	    rf.sk_client,
	    rf.sk_region,
	    tta_c.region_code,
	    rf.sk_visit_date,
	    rf.flg_visit_completed,
	    rf.sk_proposal,
	    rf.sk_contract_annulment_date,
	    rf.sk_booking,
	    rf.sk_booking_created_date,
	    rf.sk_offer,
	    rf.sk_offer_submitted_date,
	    rf.sk_offer_approved_date,
	    rf.sk_first_credit_evaluation_init,
	    rf.sk_first_credit_evaluation_positive,
	    rf.sk_tenant_first_doc_sent_date,
	    rf.sk_last_doc_analysis_approved,
	    rf.sk_credit_analysis_init_date,
	    rf.sk_credit_analysis_end_date,
	    rf.sk_credit_analysis_approved_date,
	    rf.sk_contract,
	    rf.sk_contract_created_date,
	    rf.sk_contract_signed_date,
	    fdf.funnel_flow,
	    fdf.funnel_first_touchpoint,
	    fdf.had_flow_visit,
	    fdf.had_flow_direct,
	    fdf.had_flow_tta,
	    fdf.flow_type,
	    tta_c.first_message_date,
	    tta_c.first_attendance_date,
	    tta_c.sk_house_listing || tta_c.sk_client || tta_c.agent_id as tta_id
	from fact_listing_rent_flows rf
	left join datamarts.funnel_demand_flows fdf
	  on rf.sk_rent_flow = fdf.sk_rent_flow
	full outer join tta_complete tta_c
	  on rf.sk_house_listing = tta_c.sk_house_listing
	  and rf.sk_client = tta_c.sk_client
),
messages_sent as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  'Other' as demand_channel,
  count(distinct rf.tta_id) as messages_sent_tta,
  null::bigint as registered_agent_supports,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_init,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_completed,
  null::bigint as credit_processed,
  null::bigint as credit_approved,
  null::bigint as contract_created,
  null::bigint as contract_signed,
  null::bigint  as contract_ended
from dim_date dd
join rent_flows_adap rf
  on date(rf.first_message_date) = dd.date
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join (select distinct city_group, region_code from dim_region) dr
  on rf.region_code = dr.region_code
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
agent_supports as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  'Other' as demand_channel,
  null::bigint as messages_sent_tta,
  count(distinct rf.tta_id) as registered_agent_supports,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_init,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_completed,
  null::bigint as credit_processed,
  null::bigint as credit_approved,
  null::bigint as contract_created,
  null::bigint as contract_signed,
  null::bigint  as contract_ended
from dim_date dd
join rent_flows_adap rf
  on date(rf.first_attendance_date) = dd.date
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
visits_booked as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  db.mkt_channel as demand_channel,
  null::bigint as messages_sent_tta,
  null::bigint as registered_agent_supports,
  count(distinct rf.sk_booking) as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_init,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_completed,
  null::bigint as credit_processed,
  null::bigint as credit_approved,
  null::bigint as contract_created,
  null::bigint as contract_signed,
  null::bigint  as contract_ended
from dim_date dd
join rent_flows_adap rf
  on dd.sk_date = rf.sk_booking_created_date
  and rf.sk_booking_created_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_booking db
  on rf.sk_booking = db.sk_booking
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
visits_completed as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  db.mkt_channel as demand_channel,
  null::bigint as messages_sent_tta,
  null::bigint as registered_agent_supports,
  null::bigint as visits_booked,
  count(distinct rf.sk_booking) as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_init,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_completed,
  null::bigint as credit_processed,
  null::bigint as credit_approved,
  null::bigint as contract_created,
  null::bigint as contract_signed,
  null::bigint  as contract_ended
from dim_date dd
join rent_flows_adap rf
  on dd.sk_date = rf.sk_visit_date
  and rf.sk_visit_date > 0 and rf.flg_visit_completed = 1
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_booking db
  on rf.sk_booking = db.sk_booking
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
offer_submitted as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  dof.mkt_medium as demand_channel,
  null::bigint as messages_sent_tta,
  null::bigint as registered_agent_supports,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  count(distinct rf.sk_offer) as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_init,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_completed,
  null::bigint as credit_processed,
  null::bigint as credit_approved,
  null::bigint as contract_created,
  null::bigint as contract_signed,
  null::bigint  as contract_ended
from dim_date dd
join rent_flows_adap rf
  on dd.sk_date = rf.sk_offer_submitted_date
  and rf.sk_offer_submitted_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date"between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
offer_approved as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  dof.mkt_medium as demand_channel,
  null::bigint as messages_sent_tta,
  null::bigint as registered_agent_supports,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  count(distinct rf.sk_offer) as offer_approved,
  null::bigint as credit_evaluation_init,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_completed,
  null::bigint as credit_processed,
  null::bigint as credit_approved,
  null::bigint as contract_created,
  null::bigint as contract_signed,
  null::bigint  as contract_ended
from dim_date dd
join rent_flows_adap rf
  on dd.sk_date = rf.sk_offer_approved_date
  and rf.sk_offer_approved_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
credit_evaluation_init as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  dof.mkt_medium as demand_channel,
  null::bigint as messages_sent_tta,
  null::bigint as registered_agent_supports,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  count(distinct rf.sk_offer) as credit_evaluation_init,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_completed,
  null::bigint as credit_processed,
  null::bigint as credit_approved,
  null::bigint as contract_created,
  null::bigint as contract_signed,
  null::bigint  as contract_ended
from dim_date dd
join rent_flows_adap rf
  on dd.sk_date = rf.sk_first_credit_evaluation_init
  and rf.sk_first_credit_evaluation_init > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
credit_evaluation_positive as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  dof.mkt_medium as demand_channel,
  null::bigint as messages_sent_tta,
  null::bigint as registered_agent_supports,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_init,
  count(distinct rf.sk_offer) as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_completed,
  null::bigint as credit_processed,
  null::bigint as credit_approved,
  null::bigint as contract_created,
  null::bigint as contract_signed,
  null::bigint  as contract_ended
from dim_date dd
join rent_flows_adap rf
  on dd.sk_date = rf.sk_first_credit_evaluation_positive
  and rf.sk_first_credit_evaluation_positive > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
doc_sent as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  dof.mkt_medium as demand_channel,
  null::bigint as messages_sent_tta,
  null::bigint as registered_agent_supports,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_init,
  null::bigint as credit_evaluation_positive,
  count(distinct rf.sk_offer) as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_completed,
  null::bigint as credit_processed,
  null::bigint as credit_approved,
  null::bigint as contract_created,
  null::bigint as contract_signed,
  null::bigint  as contract_ended
from dim_date dd
join rent_flows_adap rf
  on dd.sk_date = rf.sk_tenant_first_doc_sent_date
  and rf.sk_tenant_first_doc_sent_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
doc_approved as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  dof.mkt_medium as demand_channel,
  null::bigint as messages_sent_tta,
  null::bigint as registered_agent_supports,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_init,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  count(distinct rf.sk_offer) as doc_approved,
  null::bigint as doc_completed,
  null::bigint as credit_processed,
  null::bigint as credit_approved,
  null::bigint as contract_created,
  null::bigint as contract_signed,
  null::bigint  as contract_ended
from dim_date dd
join rent_flows_adap rf
  on dd.sk_date = rf.sk_last_doc_analysis_approved
  and rf.sk_last_doc_analysis_approved > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
doc_completed as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  dof.mkt_medium as demand_channel,
  null::bigint as messages_sent_tta,
  null::bigint as registered_agent_supports,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_init,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  count(distinct rf.sk_offer) as doc_completed,
  null::bigint as credit_processed,
  null::bigint as credit_approved,
  null::bigint as contract_created,
  null::bigint as contract_signed,
  null::bigint  as contract_ended
from dim_date dd
join rent_flows_adap rf
  on dd.sk_date = rf.sk_credit_analysis_init_date
  and rf.sk_credit_analysis_init_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
credit_processed as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  dof.mkt_medium as demand_channel,
  null::bigint as messages_sent_tta,
  null::bigint as registered_agent_supports,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_init,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_completed,
  count(distinct rf.sk_offer) as credit_processed,
  null::bigint as credit_approved,
  null::bigint as contract_created,
  null::bigint as contract_signed,
  null::bigint  as contract_ended
from dim_date dd
join rent_flows_adap rf
  on dd.sk_date = rf.sk_credit_analysis_end_date
  and rf.sk_credit_analysis_end_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
credit_approved as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  dof.mkt_medium as demand_channel,
  null::bigint as messages_sent_tta,
  null::bigint as registered_agent_supports,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_init,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_completed,
  null::bigint as credit_processed,
  count(distinct rf.sk_offer) as credit_approved,
  null::bigint as contract_created,
  null::bigint as contract_signed,
  null::bigint  as contract_ended
from dim_date dd
join rent_flows_adap rf
  on dd.sk_date = rf.sk_credit_analysis_approved_date
  and rf.sk_credit_analysis_approved_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
contract_created as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  dof.mkt_medium as demand_channel,
  null::bigint as messages_sent_tta,
  null::bigint as registered_agent_supports,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_init,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_completed,
  null::bigint as credit_processed,
  null::bigint as credit_approved,
  count(distinct rf.sk_contract) as contract_created,
  null::bigint as contract_signed,
  null::bigint  as contract_ended
from dim_date dd
join rent_flows_adap rf
  on dd.sk_date = rf.sk_contract_created_date
  and rf.sk_contract_created_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
contract_signed as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  dof.mkt_medium as demand_channel,
  null::bigint as visits_booked,
  null::bigint as messages_sent_tta,
  null::bigint as registered_agent_supports,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_init,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_completed,
  null::bigint as credit_processed,
  null::bigint as credit_approved,
  null::bigint as contract_created,
  count(distinct rf.sk_contract) as contract_signed,
  null::bigint  as contract_ended
from dim_date dd
join rent_flows_adap rf
  on dd.sk_date = rf.sk_contract_signed_date
  and rf.sk_contract_signed_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
contract_ended as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  rf.funnel_flow,
  rf.funnel_first_touchpoint,
  rf.had_flow_visit,
  rf.had_flow_direct,
  rf.had_flow_tta,
  rf.flow_type,
  dof.mkt_medium as demand_channel,
  null::bigint as messages_sent_tta,
  null::bigint as registered_agent_supports,
  null::bigint as visits_booked,
  null::bigint as visits_completed,
  null::bigint as offer_submitted,
  null::bigint as offer_approved,
  null::bigint as credit_evaluation_init,
  null::bigint as credit_evaluation_positive,
  null::bigint as doc_sent,
  null::bigint as doc_approved,
  null::bigint as doc_completed,
  null::bigint as credit_processed,
  null::bigint as credit_approved,
  null::bigint as contract_created,
  null::bigint as contract_signed,
  count(distinct rf.sk_contract) as contract_ended
from dim_date dd
join rent_flows_adap rf
  on dd.sk_date = rf.sk_contract_annulment_date
  and rf.sk_contract_signed_date > 0 and rf.sk_contract_annulment_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
union_all as (
	select * from messages_sent
	union all
	select * from agent_supports
	union all
	select * from visits_booked
	union all
	select * from visits_completed
	union all
	select * from offer_submitted
	union all
	select * from offer_approved
	union all
	select * from credit_evaluation_init
	union all
	select * from credit_evaluation_positive
	union all
	select * from doc_sent
	union all
	select * from doc_approved
	union all
	select * from doc_completed
	union all
	select * from credit_processed
	union all
	select * from credit_approved
	union all
	select * from contract_created
	union all
	select * from contract_signed
	union all
	select * from contract_ended
),
union_all_date as (
select
  dd."date",
  ua.city_group,
  ua.is_b2b,
  ua.funnel_flow,
  ua.funnel_first_touchpoint,
  ua.had_flow_visit,
  ua.had_flow_direct,
  ua.had_flow_tta,
  ua.flow_type,
  ua.demand_channel,
  ua.messages_sent_tta,
  ua.registered_agent_supports,
  ua.visits_booked,
  ua.visits_completed,
  ua.offer_submitted,
  ua.offer_approved,
  ua.credit_evaluation_init,
  ua.credit_evaluation_positive,
  ua.doc_sent,
  ua.doc_approved,
  ua.doc_completed,
  ua.credit_processed,
  ua.credit_approved,
  ua.contract_created,
  ua.contract_signed,
  ua.contract_ended
from union_all ua
right join dim_date dd
  on ua.sk_date = dd.sk_date
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date
)
select
  "date",
  city_group,
  funnel_flow,
  funnel_first_touchpoint,
  had_flow_visit,
  had_flow_direct,
  had_flow_tta,
  flow_type,
  case when demand_channel in ('Not Mapped', 'Other') or demand_channel is null then 'Other'
       else demand_channel end as demand_channel,
  is_b2b as is_b2b_demand,
  sum(messages_sent_tta) as messages_sent_tta,
  sum(registered_agent_supports) as registered_agent_supports,
  sum(visits_booked) as visits_booked,
  sum(visits_completed) as visits_completed,
  sum(offer_submitted) as offer_submitted,
  sum(offer_approved) as offer_approved,
  sum(coalesce(credit_evaluation_init,0)) as credit_evaluation_init,
  sum(coalesce(credit_evaluation_positive,0)) as credit_evaluation_positive,
  sum(doc_sent) as doc_sent,
  sum(coalesce(doc_approved,0)) as doc_approved,
  sum(doc_completed) as doc_completed,
  sum(credit_processed) as credit_processed,
  sum(credit_approved) as credit_approved,
  sum(contract_created) as contract_created,
  sum(contract_signed) as contract_signed,
  sum(contract_ended) as contract_ended,
  current_timestamp as ts_load
from union_all
group by "date", city_group, 3, 4, 5, 6, 7, 8, 9, 10
