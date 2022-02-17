with 
lead_ as (
select
	dd."date",
	dd.sk_date,
	dr.city_group,
  case when (fhlf.mkt_origin != 'B2B' or fhlf.sk_partner = -1) then 'B2C' 
       when fhlf.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhlf.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
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
left join dim_partner dp 
  on dp.sk_partner = fhlf.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
),
prospect as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (fhlf.mkt_origin != 'B2B' or fhlf.sk_partner = -1) then 'B2C' 
       when fhlf.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhlf.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
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
left join dim_partner dp 
  on dp.sk_partner = fhlf.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
)
,
qualified as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (fhlf.mkt_origin != 'B2B' or fhlf.sk_partner = -1) then 'B2C' 
       when fhlf.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhlf.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
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
left join dim_partner dp 
  on dp.sk_partner = fhlf.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
)
,
opportunity as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (fhlf.mkt_origin != 'B2B' or fhlf.sk_partner = -1) then 'B2C' 
       when fhlf.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhlf.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
    null::bigint AS credit_evaluation_init,
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
left join dim_partner dp 
  on dp.sk_partner = fhlf.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
),
listing as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (fhlf.mkt_origin != 'B2B' or fhlf.sk_partner = -1) then 'B2C' 
       when fhlf.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhlf.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
    null::bigint AS credit_evaluation_init,
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
left join dim_partner dp 
  on dp.sk_partner = fhlf.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
),
messages_sent as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (dhl.is_b2b != true or fhl.sk_partner = -1) then 'B2C' 
       when fhl.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhl.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
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
join fact_listing_rent_flows rf
  on tta.sk_house_listing = rf.sk_house_listing
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_region dr
  on rf.sk_region = dr.sk_region
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing 
left join dim_partner dp 
  on dp.sk_partner = fhl.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
),
agent_supports as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (dhl.is_b2b != true or fhl.sk_partner = -1) then 'B2C' 
       when fhl.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhl.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
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
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing 
left join dim_partner dp 
  on dp.sk_partner = fhl.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
),
visits_booked as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (dhl.is_b2b != true or fhl.sk_partner = -1) then 'B2C' 
       when fhl.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhl.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
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
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing 
left join dim_partner dp 
  on dp.sk_partner = fhl.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
),
visits_completed as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (dhl.is_b2b != true or fhl.sk_partner = -1) then 'B2C' 
       when fhl.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhl.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
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
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing 
left join dim_partner dp 
  on dp.sk_partner = fhl.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
),
offer_submitted as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (dhl.is_b2b != true or fhl.sk_partner = -1) then 'B2C' 
       when fhl.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhl.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
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
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing 
left join dim_partner dp 
  on dp.sk_partner = fhl.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
),
offer_approved as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (dhl.is_b2b != true or fhl.sk_partner = -1) then 'B2C' 
       when fhl.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhl.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
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
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing 
left join dim_partner dp 
  on dp.sk_partner = fhl.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
),
credit_evaluation_init as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (dhl.is_b2b != true or fhl.sk_partner = -1) then 'B2C' 
       when fhl.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhl.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  COUNT(DISTINCT rf.sk_offer) AS credit_evaluation_init,
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
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing 
left join dim_partner dp 
  on dp.sk_partner = fhl.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
),
credit_evaluation_positive as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (dhl.is_b2b != true or fhl.sk_partner = -1) then 'B2C' 
       when fhl.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhl.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
  COUNT(DISTINCT rf.sk_offer) AS credit_evaluation_positive,
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
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing 
left join dim_partner dp 
  on dp.sk_partner = fhl.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
),
doc_sent as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (dhl.is_b2b != true or fhl.sk_partner = -1) then 'B2C' 
       when fhl.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhl.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
  null::bigint AS credit_evaluation_positive,
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
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing 
left join dim_partner dp 
  on dp.sk_partner = fhl.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
),
doc_approved as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (dhl.is_b2b != true or fhl.sk_partner = -1) then 'B2C' 
       when fhl.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhl.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
  null::bigint AS credit_evaluation_positive,
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
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing 
left join dim_partner dp 
  on dp.sk_partner = fhl.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
),
credit_approved as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (dhl.is_b2b != true or fhl.sk_partner = -1) then 'B2C' 
       when fhl.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhl.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
  null::bigint AS credit_evaluation_positive,
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
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing 
left join dim_partner dp 
  on dp.sk_partner = fhl.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
),
contract_created as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (dhl.is_b2b != true or fhl.sk_partner = -1) then 'B2C' 
       when fhl.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhl.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
  null::bigint AS credit_evaluation_positive,
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
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing 
left join dim_partner dp 
  on dp.sk_partner = fhl.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
),
contract_signed as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (dhl.is_b2b != true or fhl.sk_partner = -1) then 'B2C' 
       when fhl.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhl.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
  null::bigint AS credit_evaluation_positive,
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
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing 
left join dim_partner dp 
  on dp.sk_partner = fhl.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
)
,
contract_ended as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  case when (dhl.is_b2b != true or fhl.sk_partner = -1) then 'B2C' 
       when fhl.sk_partner IN (6,7,8) then 'Thaís Imobiliária' 
       when fhl.sk_partner > 50 then 'B2B - AA'
       else dp.trade_name end as partner,
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
  null::bigint AS credit_evaluation_init,
  null::bigint AS credit_evaluation_positive,
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
left join fact_house_listings fhl
  on fhl.sk_house_listing = dhl.sk_house_listing 
left join dim_partner dp 
  on dp.sk_partner = fhl.sk_partner 
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date 
group by 1, 2, 3, 4
)
,
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
  ua.partner,
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
  ua.credit_approved,
  ua.contract_created,
  ua.contract_signed,
  ua.contract_ended
from union_all ua
right join dim_date dd
  on ua.sk_date = dd.sk_date
where dd."date" between date_trunc('year',current_date) - interval '1 year' and current_date
),
agg_all as (
  select
  "date",
  city_group,
  partner,
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
  sum(credit_evaluation_init) as credit_evaluation_init,
  sum(credit_evaluation_positive) as credit_evaluation_positive,
  sum(doc_sent) as doc_sent,
  sum(doc_approved) as doc_approved,
  sum(credit_approved) as credit_approved,
  sum(contract_created) as contract_created,
  sum(contract_signed) as contract_signed,
  sum(contract_ended) as contract_ended
from union_all
group by "date", city_group, partner
)
select
	*,
	current_timestamp as ts_load
from agg_all;
