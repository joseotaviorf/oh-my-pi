query_demand = """select 
f.sk_rental_flow,
f.sk_house, -- sk_property,
f.sk_booking, 
f.sk_owner,
-- f.sk_user_affiliate,
f.sk_user_agent,
-- f.sk_user_visitor,
f.sk_user_visit_agent,
f.sk_visit,
f.sk_negotiation,
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

-- offer --
-- dof.dt_created as dt_offer_created,
dof.dt_first_sent as dt_offer_first_sent,
dof.dt_approved as dt_offer_approved, -- what is the meaning when the offer is not approved ? bug. rib will check. for now remove the date approved if the status is not approvada
dof.status as offer_status, -- ? see above

-- proposal --
dp.dt_created as dt_proposal_created,
dp.dt_proposal_approved,
-- dp.status as proposal_status, -- needed ? not needed
dp.dt_tenant_first_document_sent, --correct field? why first? the date he sent his docs for the first time

-- contract --
dc.dt_created as dt_contract_created,
dc.dt_signature as dt_contract_signature,
dc.contract_status,
db.reason_category,

-- region --
dr.region_code,
dr.city_name

from fact_demand f
left join dim_booking db on f.sk_booking = db.sk_booking
left join dim_offer dof on f.sk_offer = dof.sk_offer
left join dim_proposal dp on f.sk_proposal = dp.sk_proposal
left join dim_contract dc on f.sk_contract = dc.sk_contract
left join dim_region dr on f.sk_region = dr.sk_region

-- when a booking is cancelled AND rescheduled we want to count the new scheduling only. 
-- the status of the first one will be cancelled and the reason will be 'rescheduling'
where db.reason_category != 'Reschedule' 

;"""
