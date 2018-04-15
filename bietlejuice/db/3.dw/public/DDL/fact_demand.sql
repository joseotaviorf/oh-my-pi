drop table if exists fact_demand;
create table fact_demand (
  ods_id bigint,
  sk_property bigint,
  sk_region bigint,
  sk_rental_flow integer,
  sk_booking integer,
  sk_owner integer,
  sk_user_agent integer,
  sk_client integer,
  sk_user_visit_agent integer,
  sk_visit integer,
  sk_negotiation integer,
  sk_offer integer,
  sk_proposal integer,
  sk_contract integer,
  visit_created_from_app integer,
  visit_created_type varchar(14),
  visit_last_updated_from_app integer,
  visit_last_updated_type varchar(14),
  booking_to_visit numeric(14,4),
  offer_to_internal_analyis numeric(14,4),
  offer_to_credit_analysis_init_date numeric(14,4),
  credit_analysis_init_to_end numeric(14,4),
  proposal_approved_to_contract_signed numeric(14,4),
  dt_timestamp timestamp without time zone
) with oids
;