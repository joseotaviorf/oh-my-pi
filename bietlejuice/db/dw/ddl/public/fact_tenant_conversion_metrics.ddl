drop table if exists fact_tenant_conversion_metrics;
create table fact_tenant_conversion_metrics (
  sk_user bigint primary key,
  sk_first_booking_date integer,
  sk_first_visit_date integer,
  sk_first_offer_sent_date integer,
  sk_first_proposal_accepted_date integer,
  sk_first_signed_contract_date integer,
  visits_booked integer,
  visits_realized integer,
  visits_expected_to_happen integer,
  offers_sent integer,
  offers_approved integer,
  offers_rejected integer,
  offers_negotiating integer,
  contracts_signed integer,
  contracts_cancelled integer,
  contracts_annuled integer,
  contracts_to_be_signed integer,
  has_visits_to_happen boolean,
  is_negotiating_offers boolean,
  has_contracts_to_sign boolean,
  has_ongoing_contracts boolean,
  ts_load timestamp
)
;
