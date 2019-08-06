with
prospect as (
select
	dd."date",
	dd.sk_date,
	dr.city_group,
	coalesce(dl.is_b2b, false) is true or coalesce(dhl.is_b2b, false) is true as is_b2b,
	dl.origem as lead_origin,
	fhlf.mkt_channel,
	fhlf.mkt_medium as mkt_medium_lead,
	null as mkt_medium_demand,
	count(fhlf.sk_prospect_date) as prospects, -- this count is done on the prospect date because not all listings come from a lead, and maybe one lead brings multiple house listings
	null::integer as qualifieds,
	null::integer as opportunities,
	null::integer as first_listings,
	null::integer as visits_booked,
    null::integer as visits_completed,
    null::integer as offer_submitted,
    null::integer as offer_approved,
    null::integer as doc_sent,
    null::integer as doc_completed,
    null::integer as credit_processed,
    null::integer as credit_approved,
    null::integer as contract_created,
    null::integer as contract_signed
from dim_date dd
join fact_house_listing_flows fhlf
  on dd.sk_date = fhlf.sk_prospect_date
  and fhlf.sk_prospect_date > 0
left join dim_lead dl
  on dl.sk_lead = fhlf.sk_lead
left join dim_region dr
  on dr.sk_region = fhlf.sk_region
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhlf.sk_house_listing
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
qualified as (
select
	dd."date",
	dd.sk_date,
	dr.city_group,
	coalesce(dl.is_b2b, false) is true or coalesce(dhl.is_b2b, false) is true as is_b2b,
	dl.origem as lead_origin,
	fhlf.mkt_channel,
	fhlf.mkt_medium as mkt_medium_lead,
	null as mkt_medium_demand,
	null::integer as prospects,
	count(fhlf.sk_qualified_date) as qualifieds, -- this count is done on the qualified date because not all listings come from a lead, and maybe one lead brings multiple house listings
	null::integer as opportunities,
	null::integer as first_listings,
	null::integer as visits_booked,
    null::integer as visits_completed,
    null::integer as offer_submitted,
    null::integer as offer_approved,
    null::integer as doc_sent,
    null::integer as doc_completed,
    null::integer as credit_processed,
    null::integer as credit_approved,
    null::integer as contract_created,
    null::integer as contract_signed
from dim_date dd
join fact_house_listing_flows fhlf
  on dd.sk_date = fhlf.sk_qualified_date
  and fhlf.sk_qualified_date > 0
left join dim_lead dl
  on dl.sk_lead = fhlf.sk_lead
left join dim_region dr
  on dr.sk_region = fhlf.sk_region
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhlf.sk_house_listing
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
opportunity as (
select
	dd."date",
	dd.sk_date,
	dr.city_group,
	coalesce(dl.is_b2b, false) is true or coalesce(dhl.is_b2b, false) is true as is_b2b,
	dl.origem as lead_origin,
	fhlf.mkt_channel,
	fhlf.mkt_medium as mkt_medium_lead,
	null as mkt_medium_demand,
	null::integer as prospects,
	null::integer as qualifieds,
	count(distinct fhlf.sk_house_listing) as opportunities,
	null::integer as first_listings,
	null::integer as visits_booked,
    null::integer as visits_completed,
    null::integer as offer_submitted,
    null::integer as offer_approved,
    null::integer as doc_sent,
    null::integer as doc_completed,
    null::integer as credit_processed,
    null::integer as credit_approved,
    null::integer as contract_created,
    null::integer as contract_signed
from dim_date dd
join fact_house_listing_flows fhlf
  on dd.sk_date = fhlf.sk_opportunity_date
  and fhlf.sk_opportunity_date > 0
left join dim_lead dl
  on dl.sk_lead = fhlf.sk_lead
left join dim_region dr
  on dr.sk_region = fhlf.sk_region
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhlf.sk_house_listing
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
listing as (
select
	dd."date",
	dd.sk_date,
	dr.city_group,
	coalesce(dl.is_b2b, false) is true or coalesce(dhl.is_b2b, false) is true as is_b2b,
	dl.origem as lead_origin,
	fhlf.mkt_channel,
	fhlf.mkt_medium as mkt_medium_lead,
	null as mkt_medium_demand,
	null::integer as prospects,
	null::integer as qualifieds,
	null::integer as opportunities,
	count(fhlf.sk_first_listing_date) as first_listings,
	null::integer as visits_booked,
    null::integer as visits_completed,
    null::integer as offer_submitted,
    null::integer as offer_approved,
    null::integer as doc_sent,
    null::integer as doc_completed,
    null::integer as credit_processed,
    null::integer as credit_approved,
    null::integer as contract_created,
    null::integer as contract_signed
from dim_date dd
join fact_house_listing_flows fhlf
  on dd.sk_date = fhlf.sk_first_listing_date
  and fhlf.sk_first_listing_date > 0
left join dim_lead dl
  on dl.sk_lead = fhlf.sk_lead
left join dim_region dr
  on dr.sk_region = fhlf.sk_region
left join dim_house_listing dhl
  on dhl.sk_house_listing = fhlf.sk_house_listing
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
visits_booked as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as lead_origin,
  null as mkt_channel,
  null as mkt_medium_lead,
  db.mkt_medium as mkt_medium_demand,
  null::integer as prospects,
  null::integer as qualifieds,
  null::integer as opportunities,
  null::integer as first_listings,
  count(distinct rf.sk_booking) as visits_booked,
  null::integer as visits_completed,
  null::integer as offer_submitted,
  null::integer as offer_approved,
  null::integer as doc_sent,
  null::integer as doc_completed,
  null::integer as credit_processed,
  null::integer as credit_approved,
  null::integer as contract_created,
  null::integer as contract_signed
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
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
visits_completed as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as lead_origin,
  null as mkt_channel,
  null as mkt_medium_lead,
  db.mkt_medium as mkt_medium_demand,
  null::integer as prospects,
  null::integer as qualifieds,
  null::integer as opportunities,
  null::integer as first_listings,
  null::integer as visits_booked,
  count(distinct rf.sk_booking) as visits_completed,
  null::integer as offer_submitted,
  null::integer as offer_approved,
  null::integer as doc_sent,
  null::integer as doc_completed,
  null::integer as credit_processed,
  null::integer as credit_approved,
  null::integer as contract_created,
  null::integer as contract_signed
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
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
offer_submitted as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as lead_origin,
  null as mkt_channel,
  null as mkt_medium_lead,
  db.mkt_medium as mkt_medium_demand,
  null::integer as prospects,
  null::integer as qualifieds,
  null::integer as opportunities,
  null::integer as first_listings,
  null::integer as visits_booked,
  null::integer as visits_completed,
  count(distinct rf.sk_offer) as offer_submitted,
  null::integer as offer_approved,
  null::integer as doc_sent,
  null::integer as doc_completed,
  null::integer as credit_processed,
  null::integer as credit_approved,
  null::integer as contract_created,
  null::integer as contract_signed
from dim_date dd
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_offer_submitted_date
  and rf.sk_offer_submitted_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_booking db
  on rf.sk_booking = db.sk_booking
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date"between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
offer_approved as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as lead_origin,
  null as mkt_channel,
  null as mkt_medium_lead,
  db.mkt_medium as mkt_medium_demand,
  null::integer as prospects,
  null::integer as qualifieds,
  null::integer as opportunities,
  null::integer as first_listings,
  null::integer as visits_booked,
  null::integer as visits_completed,
  null::integer as offer_submitted,
  count(distinct rf.sk_offer) as offer_approved,
  null::integer as doc_sent,
  null::integer as doc_completed,
  null::integer as credit_processed,
  null::integer as credit_approved,
  null::integer as contract_created,
  null::integer as contract_signed
from dim_date dd
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_offer_approved_date
  and rf.sk_offer_approved_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_booking db
  on rf.sk_booking = db.sk_booking
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
doc_sent as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as lead_origin,
  null as mkt_channel,
  null as mkt_medium_lead,
  db.mkt_medium as mkt_medium_demand,
  null::integer as prospects,
  null::integer as qualifieds,
  null::integer as opportunities,
  null::integer as first_listings,
  null::integer as visits_booked,
  null::integer as visits_completed,
  null::integer as offer_submitted,
  null::integer as offer_approved,
  count(distinct rf.sk_offer) as doc_sent,
  null::integer as doc_completed,
  null::integer as credit_processed,
  null::integer as credit_approved,
  null::integer as contract_created,
  null::integer as contract_signed
from dim_date dd
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_tenant_first_doc_sent_date
  and rf.sk_tenant_first_doc_sent_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_booking db
  on rf.sk_booking = db.sk_booking
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
doc_completed as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as lead_origin,
  null as mkt_channel,
  null as mkt_medium_lead,
  db.mkt_medium as mkt_medium_demand,
  null::integer as prospects,
  null::integer as qualifieds,
  null::integer as opportunities,
  null::integer as first_listings,
  null::integer as visits_booked,
  null::integer as visits_completed,
  null::integer as offer_submitted,
  null::integer as offer_approved,
  null::integer as doc_sent,
  count(distinct rf.sk_offer) as doc_completed,
  null::integer as credit_processed,
  null::integer as credit_approved,
  null::integer as contract_created,
  null::integer as contract_signed
from dim_date dd
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_credit_analysis_init_date
  and rf.sk_credit_analysis_init_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_booking db
  on rf.sk_booking = db.sk_booking
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
credit_processed as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as lead_origin,
  null as mkt_channel,
  null as mkt_medium_lead,
  db.mkt_medium as mkt_medium_demand,
  null::integer as prospects,
  null::integer as qualifieds,
  null::integer as opportunities,
  null::integer as first_listings,
  null::integer as visits_booked,
  null::integer as visits_completed,
  null::integer as offer_submitted,
  null::integer as offer_approved,
  null::integer as doc_sent,
  null::integer as doc_completed,
  count(distinct rf.sk_offer) as credit_processed,
  null::integer as credit_approved,
  null::integer as contract_created,
  null::integer as contract_signed
from dim_date dd
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_credit_analysis_end_date
  and rf.sk_credit_analysis_end_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_booking db
  on rf.sk_booking = db.sk_booking
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
credit_approved as(
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as lead_origin,
  null as mkt_channel,
  null as mkt_medium_lead,
  db.mkt_medium as mkt_medium_demand,
  null::integer as prospects,
  null::integer as qualifieds,
  null::integer as opportunities,
  null::integer as first_listings,
  null::integer as visits_booked,
  null::integer as visits_completed,
  null::integer as offer_submitted,
  null::integer as offer_approved,
  null::integer as doc_sent,
  null::integer as doc_completed,
  null::integer as credit_processed,
  count(distinct rf.sk_offer) as credit_approved,
  null::integer as contract_created,
  null::integer as contract_signed
from dim_date dd
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_credit_analysis_approved_date
  and rf.sk_credit_analysis_approved_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_booking db
  on rf.sk_booking = db.sk_booking
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
contract_created as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as lead_origin,
  null as mkt_channel,
  null as mkt_medium_lead,
  db.mkt_medium as mkt_medium_demand,
  null::integer as prospects,
  null::integer as qualifieds,
  null::integer as opportunities,
  null::integer as first_listings,
  null::integer as visits_booked,
  null::integer as visits_completed,
  null::integer as offer_submitted,
  null::integer as offer_approved,
  null::integer as doc_sent,
  null::integer as doc_completed,
  null::integer as credit_processed,
  null::integer as credit_approved,
  count(distinct rf.sk_contract) as contract_created,
  null::integer as contract_signed
from dim_date dd
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_contract_created_date
  and rf.sk_contract_created_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_booking db
  on rf.sk_booking = db.sk_booking
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
contract_signed as (
select
  dd."date",
  dd.sk_date,
  dr.city_group,
  dhl.is_b2b,
  null as lead_origin,
  null as mkt_channel,
  null as mkt_medium_lead,
  db.mkt_medium as mkt_medium_demand,
  null::integer as prospects,
  null::integer as qualifieds,
  null::integer as opportunities,
  null::integer as first_listings,
  null::integer as visits_booked,
  null::integer as visits_completed,
  null::integer as offer_submitted,
  null::integer as offer_approved,
  null::integer as doc_sent,
  null::integer as doc_completed,
  null::integer as credit_processed,
  null::integer as credit_approved,
  null::integer as contract_created,
  count(distinct rf.sk_contract) as contract_signed
from dim_date dd
join fact_listing_rent_flows rf
  on dd.sk_date = rf.sk_contract_signed_date
  and rf.sk_contract_signed_date > 0
join dim_house_listing dhl
  on rf.sk_house_listing = dhl.sk_house_listing
left join dim_booking db
  on rf.sk_booking = db.sk_booking
left join dim_region dr
  on rf.sk_region = dr.sk_region
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date -- filter data from 4 year ago
group by 1, 2, 3, 4, 5, 6, 7, 8
),
union_all as (
	select * from prospect
	union all
	select * from qualified
	union all
	select * from opportunity
	union all
	select * from listing
	union all
	select * from visits_booked
	union all
	select * from visits_completed
	union all
	select * from offer_submitted
	union all
	select * from offer_approved
	union all
	select * from doc_sent
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
),
union_all_date as (
select
	dd."date",
	ua.city_group,
  	ua.is_b2b,
    ua.lead_origin,
    ua.mkt_channel,
    ua.mkt_medium_lead,
    ua.mkt_medium_demand,
    ua.prospects,
    ua.qualifieds,
    ua.opportunities,
    ua.first_listings,
    ua.visits_booked,
    ua.visits_completed,
    ua.offer_submitted,
    ua.offer_approved,
    ua.doc_sent,
    ua.doc_completed,
    ua.credit_processed,
    ua.credit_approved,
    ua.contract_created,
    ua.contract_signed
from union_all ua
right join dim_date dd
  on ua.sk_date = dd.sk_date
where dd."date" between date_trunc('year',current_date) - interval '4 year' and current_date
),
agg_all as (
select
	"date",
	city_group,
	case when is_b2b is true then 'B2B'
	     else
    case when lead_origin = 'PriceSuggestion' then 'Calculadora'
	     else
	     case when mkt_medium_lead in ('SEM non-branded', 'Display', 'Retargeting', 'Online Networks', 'Online Classifieds') then 'OnlinePaid'
	          when mkt_medium_lead in ('SEM branded', 'Social', 'Notifications', 'Direct') then 'Organic'
	          when mkt_medium_lead in ('Crawling', 'Not Mapped', 'Lost Tracking', 'Content', 'Portal', 'Recovered Leads') then 'Other'
	     else mkt_medium_lead end end end as mkt_medium_lead,
	case when is_b2b is true then 'B2B'
	     else
    case when mkt_medium_demand = 'Agents' then 'Agents'
         when mkt_medium_demand = 'Online Classifieds' then 'OnlineClassifieds'
         when mkt_medium_demand in ('CX','Direct','Notifications','SEM branded','Social') then 'Organic'
         when mkt_medium_demand in ('Display','Retargeting','SEM non-branded') then 'Online Paid'
         when mkt_medium_demand in ('Not Mapped', 'Lost Tracking','Not Tracked', 'Other') then 'Other'
         else mkt_medium_demand end end as mkt_medium_demand,
	sum(prospects) as prospects,
    sum(qualifieds) as qualifieds,
    sum(opportunities) as opportunities,
    sum(first_listings) as first_listings,
	sum(visits_booked) as visits_booked,
    sum(visits_completed) as visits_completed,
    sum(offer_submitted) as offer_submitted,
    sum(offer_approved) as offer_approved,
    sum(doc_sent) as doc_sent,
    sum(doc_completed) as doc_completed,
    sum(credit_processed) as credit_processed,
    sum(credit_approved) as credit_approved,
    sum(contract_created) as contract_created,
    sum(contract_signed) as contract_signed
from union_all
group by "date", city_group, 3, 4
order by "date", city_group, 3, 4
)
select * from agg_all
;
