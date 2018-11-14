drop view if exists unit_economics.vw_mgmt_insurance_pis_cofins;

create or replace view unit_economics.vw_mgmt_insurance_pis_cofins as 
select
	sk_house_listing,
	property_id,
	contract_id,
	-(vl_insurance_fee * 0.0925) as vl_st_pis_cofins,
	(date_trunc('month', dt_cash_flow) + interval '19 day')::date as dt_cash_flow,
	flg_expected
from 
	unit_economics.vw_mgmt_insurance_fee
;