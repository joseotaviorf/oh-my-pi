WITH
contract_revision AS (
SELECT
	id_contract,
  	TO_TIMESTAMP(REPLACE(REPLACE(get_json_object(contract_data, '$.signatureDate'), 'T', ' '), 'Z', ''), 'yyyy-MM-dd HH:mm:ss') AS ts_signature,
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
	cr.ts_signature,
	c.ts_created,
	c.ts_updated
FROM 
	datalake_billing_clean.contract c
LEFT JOIN 
	contract_revision cr
	ON c.id = cr.id_contract


