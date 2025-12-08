WITH
contract_revision AS (
SELECT
	id_contract,
  	TO_TIMESTAMP(REPLACE(REPLACE(get_json_object(contract_data, '$.signatureDate'), 'T', ' '), 'Z', ''), 'yyyy-MM-dd HH:mm:ss') AS ts_signature,
  	TO_TIMESTAMP(REPLACE(REPLACE(get_json_object(contract_data, '$.startCharge'), 'T', ' '), 'Z', ''), 'yyyy-MM-dd HH:mm:ss') AS ts_charge_started,
  	TO_TIMESTAMP(REPLACE(REPLACE(get_json_object(contract_data, '$.endCharge'), 'T', ' '), 'Z', ''), 'yyyy-MM-dd HH:mm:ss') AS ts_charge_ended,
    CAST(get_json_object(contract_data, '$.rentalPaidInAdvance') AS BOOLEAN) AS is_rental_paid_in_advance,
    CAST(get_json_object(contract_data, '$.condominiumAmount') AS DECIMAL (10,2)) AS condominium_amount,
    CAST(get_json_object(contract_data, '$.homeInsuranceAmount') AS DECIMAL(10,2)) AS home_insurance_amount,
    CAST(get_json_object(contract_data, '$.brokerageFee') AS DECIMAL(10,2)) AS brokerage_fee,
    CAST(get_json_object(contract_data, '$.tenantServiceFee') AS DOUBLE) AS tenant_service_fee,
    CAST(get_json_object(contract_data, '$.administrationFee') AS DOUBLE) AS admin_fee,
    get_json_object(contract_data, '$.brokerageFeeBaseOn') AS brokerage_based_fee,
    CAST(get_json_object(contract_data, '$.admFeeMinimumAmount') AS DECIMAL(10,2)) AS min_admin_fee,
    CAST(get_json_object(contract_data, '$.rentals[0].amount') AS DECIMAL(10,2)) AS last_rental,
    CAST(get_json_object(contract_data, '$.iptus[0].amount') AS DECIMAL(10,2)) AS last_iptu,
	ts_created
FROM
	datalake_billing_clean.contract_revision
QUALIFY
	ROW_NUMBER() OVER(PARTITION BY id_contract ORDER BY DATE(ts_created) DESC) = 1
)
SELECT
	c.id,
	c.uuid_recurrence,
	c.status,
	c.current_revision,
	cr.condominium_amount,
	cr.home_insurance_amount,
	cr.brokerage_fee,
	cr.tenant_service_fee,
	cr.admin_fee,
	cr.brokerage_based_fee,
	cr.min_admin_fee,
	cr.last_rental,
  	cr.last_iptu,
  	cr.is_rental_paid_in_advance,
	cr.ts_signature,
  	cr.ts_charge_started,
  	cr.ts_charge_ended,
	c.ts_created,
	c.ts_updated,
	NOW() AS ts_load
FROM
	datalake_billing_clean.contract c
LEFT JOIN
	contract_revision cr
	ON c.id = cr.id_contract
