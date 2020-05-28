drop table if exists public.fact_tenant_conversion_metrics;
create table public.fact_tenant_conversion_metrics (
  sk_user bigint primary key,
  sk_first_booking_date bigint,
  sk_first_visit_date bigint,
  sk_first_offer_sent_date bigint,
  sk_first_proposal_accepted_date bigint,
  sk_first_signed_contract_date bigint,
  visits_booked bigint,
  visits_realized bigint,
  visits_expected_to_happen bigint,
  offers_sent bigint,
  offers_approved bigint,
  offers_rejected bigint,
  offers_negotiating bigint,
  contracts_signed bigint,
  contracts_cancelled bigint,
  contracts_annuled bigint,
  contracts_to_be_signed bigint,
  has_visits_to_happen boolean,
  is_negotiating_offers boolean,
  has_contracts_to_sign boolean,
  has_ongoing_contracts boolean,
  ts_load timestamp
)
;
