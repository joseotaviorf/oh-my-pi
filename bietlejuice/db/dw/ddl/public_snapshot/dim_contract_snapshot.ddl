CREATE TABLE IF NOT EXISTS public_snapshot.dim_contract_snapshot
(
	sk_contract BIGINT NOT NULL  ENCODE RAW
	,id_contract BIGINT   ENCODE az64
	,country_code VARCHAR(256)   ENCODE lzo
	,rent NUMERIC(14,2)   ENCODE az64
	,first_rent_charged NUMERIC(14,2)   ENCODE az64
	,day_month_due SMALLINT   ENCODE az64
	,guarantee VARCHAR(256)   ENCODE lzo
	,"type" VARCHAR(256)   ENCODE lzo
	,status VARCHAR(256)   ENCODE lzo
	,rental_administrator VARCHAR(256)   ENCODE lzo
	,condo_payer VARCHAR(256)   ENCODE lzo
	,condo_responsible VARCHAR(256)   ENCODE lzo
	,iptu_payer VARCHAR(256)   ENCODE lzo
	,iptu_responsible VARCHAR(256)   ENCODE lzo
	,rental_insurance_installments SMALLINT   ENCODE az64
	,rental_insurance_value NUMERIC(14,2)   ENCODE az64
	,home_insurance_installments SMALLINT   ENCODE az64
	,home_insurance_value NUMERIC(14,2)   ENCODE az64
	,first_rental_commission NUMERIC(14,2)   ENCODE az64
	,monthly_administration_fee NUMERIC(5,4)   ENCODE az64
	,condo NUMERIC(14,2)   ENCODE az64
	,iptu NUMERIC(14,2)   ENCODE az64
	,tenant_service_fee NUMERIC(5,2)   ENCODE az64
	,agent_brokerage_share NUMERIC(5,2)   ENCODE az64
	,signature_type VARCHAR(256)   ENCODE lzo
	,closing_status VARCHAR(256)   ENCODE lzo
	,cancellation_reason VARCHAR(256)   ENCODE lzo
	,version VARCHAR(256)   ENCODE lzo
	,is_b2b BOOLEAN   ENCODE RAW
	,is_contract_b2b BOOLEAN   ENCODE RAW
	,contract_partner_type VARCHAR(256)   ENCODE lzo
	,b2b_type VARCHAR(256)   ENCODE lzo
	,b2b_prime_type VARCHAR(256)   ENCODE lzo
	,contract_plan VARCHAR(256)   ENCODE lzo
	,administration_split_percentage NUMERIC(5,2)   ENCODE az64
	,brokerage_split_percentage NUMERIC(5,2)   ENCODE az64
	,is_ongoing_contract BOOLEAN   ENCODE RAW
	,is_tenant_service_fee_opt_out BOOLEAN   ENCODE RAW
	,is_exit_inspection_opted_out BOOLEAN   ENCODE RAW
	,dt_start DATE   ENCODE az64
	,dt_entrance DATE   ENCODE az64
	,dt_intended_end DATE   ENCODE az64
	,dt_annulment DATE   ENCODE az64
	,ts_created TIMESTAMP WITHOUT TIME ZONE   ENCODE az64
	,ts_updated TIMESTAMP WITHOUT TIME ZONE   ENCODE az64
	,ts_expected_termination TIMESTAMP WITHOUT TIME ZONE   ENCODE az64
	,ts_signature TIMESTAMP WITHOUT TIME ZONE   ENCODE az64
	,ts_draft_approved TIMESTAMP WITHOUT TIME ZONE   ENCODE az64
	,ts_canceled TIMESTAMP WITHOUT TIME ZONE   ENCODE az64
	,ts_tenant_service_fee_opt_out TIMESTAMP WITHOUT TIME ZONE   ENCODE az64
	,ts_analyst_annulment_input TIMESTAMP WITHOUT TIME ZONE   ENCODE az64
	,ts_snapshot TIMESTAMP WITHOUT TIME ZONE   ENCODE az64
	,PRIMARY KEY (sk_contract)
)
;

ALTER TABLE public_snapshot.dim_contract_snapshot owner to databricks;