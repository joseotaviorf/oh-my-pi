query_demand = """select
dpt.id as sk_house,
dpt.min_version_time as dt_publication,
f.sk_rent_flow,
f.sk_booking,
f.sk_owner,
f.sk_client,
-- f.sk_user_affiliate,
f.sk_user_agent,
-- f.sk_user_visitor,
-- f.sk_user_visit_agent,
f.sk_visit,
-- f.sk_negotiation,
f.sk_offer,
f.sk_proposal,
f.sk_contract,

-- f.sk_first_listing_date,
-- f.sk_listing_date,
-- ?f.sk_booking_created_date, -- compare with with db.dt_created
-- ?f.sk_visit_date, -- compare with db.dt_scheduling_created. ok
-- f.sk_visitor_user_signup_date,
-- ?f.sk_offer_created_date, -- compare with do.dt_offer_created
-- ?f.sk_contract_signed_date, -- same as dt_proposal_approved?
-- f.sk_user_agent_date -- meaning?

-- booking --
-- db.id_booking,
db.visit_follow_up,
--db.visit_type? ...
db.dt_created as dt_booking_created,
db.dt_scheduling as dt_booking_scheduling,
db.reason_category,

-- offer --
-- dof.dt_created as dt_offer_created,
dof.dt_first_sent as dt_offer_first_sent,
case when dof.status='Aprovada' then dof.dt_analysis else null end as dt_offer_approved,
dof.status as offer_status,

-- proposal --
dp.dt_created as dt_proposal_created,
-- dp.dt_proposal_approved, -- this is the date in admin. pbi uses the date in SH (next line)
cast(f.sk_credit_analysis_approved_date as text), -- to_date(, 'YYYYMMDD') does not work. as dt_credit_analysis_approved,
-- dp.status as proposal_status, -- needed ? not needed
dp.dt_tenant_first_document_sent,
dp.dt_credit_analysis_init,

-- contract --
dc.dt_created as dt_contract_created,
dc.dt_signature as dt_contract_signature,
dc.contract_status,


-- region --
dr.region_code,
dr.city_name

from dim_property dpt
left join fact_demand f on dpt.sk_property = f.sk_house
left join dim_booking db on f.sk_booking = db.sk_booking
left join dim_offer dof on f.sk_offer = dof.sk_offer
left join dim_proposal dp on f.sk_proposal = dp.sk_proposal
left join dim_contract dc on f.sk_contract = dc.sk_contract
left join dim_region dr on f.sk_region = dr.sk_region
;"""
