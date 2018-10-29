drop view if exists vw_dim_contract;
create view vw_dim_contract as
select
  id as sk_contract,
  id as id_contract,
  rent,
  day_month_due,
  guarantee,
  type,
  status,
  dt_start,
  ts_signature,
  ts_draft_approved,
  dt_entrance,
  dt_intended_end,
  dt_annulment,
  condo_payer,
  condo_responsible,
  iptu_payer,
  iptu_responsible,
  rental_insurance_installments,
  rental_insurance_value,
  home_insurance_installments,
  home_insurance_value,
  first_rental_commission,
  condo,
  iptu,
  signature_type,
  closing_status,
  ts_created,
  ts_updated,
  cancellation_reason,
  now() as ts_load
from contract
;


