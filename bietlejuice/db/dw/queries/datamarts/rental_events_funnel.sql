with
lead_ as (
select
	dd."date",
	dd.sk_date,
	dr.city_group,
	null::boolean as is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' then fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' then 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	null as demand_channel,
  	count(fhlf.sk_lead_date) as leads,
	null::bigint as prospects, -- this count is done on the prospect date because not all listings come from a lead, and maybe one lead brings multiple house listings
	null::bigint as qualifieds,
	null::bigint as opportunities,
	null::bigint as first_listings,
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
  null::bigint  as contract_ended
from dim_date dd
join fact_house_listing_flows fhlf
  on dd.sk_date = fhlf.sk_lead_date
  and fhlf.sk_lead_date > 0
left join dim_region dr
  on dr.sk_region = fhlf.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
prospect as (
select
	dd."date",
	dd.sk_date,
	dr.city_group,
	null::boolean as is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' then fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' then 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	null as demand_channel,
  null::bigint as leads,
	count(fhlf.sk_prospect_date) as prospects, -- this count is done on the prospect date because not all listings come from a lead, and maybe one lead brings multiple house listings
	null::bigint as qualifieds,
	null::bigint as opportunities,
	null::bigint as first_listings,
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
  null::bigint  as contract_ended
from dim_date dd
join fact_house_listing_flows fhlf
  on dd.sk_date = fhlf.sk_prospect_date
  and fhlf.sk_prospect_date > 0
left join dim_region dr
  on dr.sk_region = fhlf.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
qualified as (
select
	dd."date",
	dd.sk_date,
	dr.city_group,
	null::boolean as is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' then fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' then 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	null as demand_channel,
  null::bigint as leads,
	null::bigint as prospects,
	count(fhlf.sk_qualified_date) as qualifieds, -- this count is done on the qualified date because not all listings come from a lead, and maybe one lead brings multiple house listings
	null::bigint as opportunities,
	null::bigint as first_listings,
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
  null::bigint  as contract_ended
from dim_date dd
join fact_house_listing_flows fhlf
  on dd.sk_date = fhlf.sk_qualified_date
  and fhlf.sk_qualified_date > 0
left join dim_region dr
  on dr.sk_region = fhlf.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
opportunity as (
select
	dd."date",
	dd.sk_date,
	dr.city_group,
	null::boolean as is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' then fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' then 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	null as demand_channel,
  null::bigint as leads,
	null::bigint as prospects,
	null::bigint as qualifieds,
	count(distinct fhlf.sk_house_listing) as opportunities,
	null::bigint as first_listings,
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
  null::bigint  as contract_ended
from dim_date dd
join fact_house_listing_flows fhlf
  on dd.sk_date = fhlf.sk_opportunity_date
  and fhlf.sk_opportunity_date > 0
left join dim_region dr
  on dr.sk_region = fhlf.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
listing as (
select
	dd."date",
	dd.sk_date,
	dr.city_group,
	null::boolean as is_b2b,
	fhlf.mkt_origin AS supply_mkt_origin,
	fhlf.mkt_channel AS supply_mkt_channel,
	CASE
	    WHEN fhlf.mkt_origin = 'B2B' then fhlf.mkt_origin
	    WHEN fhlf.mkt_completion = 'Full Self-Service' then 'FSS'
	    ELSE 'IS'
		END AS lead_context,
	null as demand_channel,
  null::bigint as leads,
	null::bigint as prospects,
	null::bigint as qualifieds,
	null::bigint as opportunities,
	count(fhlf.sk_first_listing_date) as first_listings,
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
  null::bigint  as contract_ended
from dim_date dd
join fact_house_listing_flows fhlf
  on dd.sk_date = fhlf.sk_first_listing_date
  and fhlf.sk_first_listing_date > 0
left join dim_region dr
  on dr.sk_region = fhlf.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
messages_sent as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  'Other' as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
  count(distinct (tta.agent_id || tta.tenant_id || tta.sk_house_listing)) as messages_sent_tta,
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
join datamarts.talk_to_agent tta
  on date(tta.first_message_ts) = dd.date
join dim_house_listing dhl
  on tta.sk_house_listing = dhl.sk_house_listing
left join (select distinct city_group, region_code from dim_region) dr
  on tta.region_code = dr.region_code
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
agent_supports as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  'Other' as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
  null::bigint as messages_sent_tta,
  count(distinct (tta.agent_id || tta.tenant_id || tta.sk_house_listing)) as registered_agent_supports,
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
join datamarts.talk_to_agent tta
  on date(tta.first_attendance_ts) = dd.date
join fact_listing_rent_flows rf
  on tta.sk_house_listing = rf.sk_house_listing
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
visits_booked as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  db.mkt_channel as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
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
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_booking_created_date
  and rf.sk_booking_created_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_booking db
  on rf.sk_booking = db.sk_booking
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
visits_completed as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  db.mkt_channel as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
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
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_visit_date
  and rf.sk_visit_date > 0 and rf.flg_visit_completed = 1
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_booking db
  on rf.sk_booking = db.sk_booking
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
offer_submitted as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  dof.mkt_medium as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
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
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_offer_submitted_date
  and rf.sk_offer_submitted_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date"between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
offer_approved as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  dof.mkt_medium as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
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
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_offer_approved_date
  and rf.sk_offer_approved_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
credit_evaluation_init as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  dof.mkt_medium as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
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
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_first_credit_evaluation_init
  and rf.sk_first_credit_evaluation_init > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
credit_evaluation_positive as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  dof.mkt_medium as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
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
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_last_credit_evaluation_positive
  and rf.sk_last_credit_evaluation_positive > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
doc_sent as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  dof.mkt_medium as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
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
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_tenant_first_doc_sent_date
  and rf.sk_tenant_first_doc_sent_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
doc_approved as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  dof.mkt_medium as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
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
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_last_doc_analysis_approved
  and rf.sk_last_doc_analysis_approved > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
doc_completed as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  dof.mkt_medium as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
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
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_credit_analysis_init_date
  and rf.sk_credit_analysis_init_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
credit_processed as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  dof.mkt_medium as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
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
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_credit_analysis_end_date
  and rf.sk_credit_analysis_end_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
credit_approved as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  dof.mkt_medium as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
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
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_credit_analysis_approved_date
  and rf.sk_credit_analysis_approved_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
contract_created as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  dof.mkt_medium as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
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
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_contract_created_date
  and rf.sk_contract_created_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
contract_signed as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  dof.mkt_medium as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
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
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_contract_signed_date
  and rf.sk_contract_signed_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
contract_ended as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as supply_mkt_origin,
  null as supply_mkt_channel,
  null AS lead_context,
  dof.mkt_medium as demand_channel,
  null::bigint as leads,
  null::bigint as prospects,
  null::bigint as qualifieds,
  null::bigint as opportunities,
  null::bigint as first_listings,
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
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_contract_annulment_date
  and rf.sk_contract_signed_date > 0 and rf.sk_contract_annulment_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_offer dof
  on rf.sk_offer = dof.sk_offer
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 years ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
union_all as (
  select * from lead_
	union all
	select * from prospect
	union all
	select * from qualified
	union all
	select * from opportunity
	union all
	select * from listing
	union all
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
  ua.supply_mkt_origin,
  ua.supply_mkt_channel,
  ua.lead_context,
  ua.demand_channel,
  ua.leads,
  ua.prospects,
  ua.qualifieds,
  ua.opportunities,
  ua.first_listings,
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
	supply_mkt_origin,
  	supply_mkt_channel,
  	lead_context,
    case when demand_channel in ('Not Mapped', 'Other') or demand_channel is null then 'Other'
         else demand_channel end as demand_channel,
  is_b2b as is_b2b_demand,
  sum(leads) as leads,
  sum(prospects) as prospects,
  sum(qualifieds) as qualifieds,
  sum(opportunities) as opportunities,
  sum(first_listings) as first_listings,
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
group by "date", city_group, 3, 4, 5, 6, 7;