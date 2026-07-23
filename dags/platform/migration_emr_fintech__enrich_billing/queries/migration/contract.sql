WITH contract_revision AS (
  SELECT
    id_contract,
    ts_signature,
    ts_charge_started,
    ts_charge_ended,
    ts_start_period,
    ts_end_period,
    country,
    contract_version,
    guarantee,
    rental_administrator,
    landlord_legal_person,
    landlord_transfer_funds_day,
    is_rental_paid_in_advance,
    condominium_amount,
    home_insurance_amount,
    brokerage_fee,
    tenant_service_fee,
    admin_fee,
    brokerage_based_fee,
    min_admin_fee,
    last_rental,
    last_iptu,
    ts_created
  FROM (
    SELECT
      id_contract,
      TO_TIMESTAMP(
        REPLACE(REPLACE(GET_JSON_OBJECT(contract_data, signatureDate), 'T', ' '), 'Z', ''),
        'yyyy-MM-dd HH:mm:ss'
      ) AS ts_signature,
      TO_TIMESTAMP(
        REPLACE(REPLACE(GET_JSON_OBJECT(contract_data, startCharge), 'T', ' '), 'Z', ''),
        'yyyy-MM-dd HH:mm:ss'
      ) AS ts_charge_started,
      TO_TIMESTAMP(
        REPLACE(REPLACE(GET_JSON_OBJECT(contract_data, endCharge), 'T', ' '), 'Z', ''),
        'yyyy-MM-dd HH:mm:ss'
      ) AS ts_charge_ended,
      TO_TIMESTAMP(
        REPLACE(REPLACE(GET_JSON_OBJECT(contract_data, startPeriod), 'T', ' '), 'Z', ''),
        'yyyy-MM-dd HH:mm:ss'
      ) AS ts_start_period,
      TO_TIMESTAMP(
        REPLACE(REPLACE(GET_JSON_OBJECT(contract_data, endPeriod), 'T', ' '), 'Z', ''),
        'yyyy-MM-dd HH:mm:ss'
      ) AS ts_end_period,
      GET_JSON_OBJECT(contract_data, country) AS country,
      GET_JSON_OBJECT(contract_data, version) AS contract_version,
      GET_JSON_OBJECT(contract_data, guarantee) AS guarantee,
      GET_JSON_OBJECT(contract_data, rentalAdministrator) AS rental_administrator,
      GET_JSON_OBJECT(contract_data, landlordLegalPerson) AS landlord_legal_person,
      CAST(GET_JSON_OBJECT(contract_data, landlordTransferFundsDay) AS INT) AS landlord_transfer_funds_day,
      CAST(GET_JSON_OBJECT(contract_data, rentalPaidInAdvance) AS BOOLEAN) AS is_rental_paid_in_advance,
      CAST(GET_JSON_OBJECT(contract_data, condominiumAmount) AS DECIMAL(10, 2)) AS condominium_amount,
      CAST(GET_JSON_OBJECT(contract_data, homeInsuranceAmount) AS DECIMAL(10, 2)) AS home_insurance_amount,
      CAST(GET_JSON_OBJECT(contract_data, brokerageFee) AS DECIMAL(10, 2)) AS brokerage_fee,
      CAST(GET_JSON_OBJECT(contract_data, tenantServiceFee) AS DOUBLE) AS tenant_service_fee,
      CAST(GET_JSON_OBJECT(contract_data, administrationFee) AS DOUBLE) AS admin_fee,
      GET_JSON_OBJECT(contract_data, brokerageFeeBaseOn) AS brokerage_based_fee,
      CAST(GET_JSON_OBJECT(contract_data, admFeeMinimumAmount) AS DECIMAL(10, 2)) AS min_admin_fee,
      ELEMENT_AT(
        ARRAY_SORT(
          FROM_JSON(GET_JSON_OBJECT(contract_data, rentals), 'ARRAY<STRUCT<since:INT, amount:DOUBLE>>')
        ),
        -1
      ).amount AS last_rental,
      ELEMENT_AT(
        ARRAY_SORT(
          FROM_JSON(GET_JSON_OBJECT(contract_data, iptus), 'ARRAY<STRUCT<since:INT, amount:DOUBLE>>')
        ),
        -1
      ).amount AS last_iptu,
      ts_created,
      ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY CAST(ts_created AS DATE) DESC) AS _w
    FROM datalake_billing_clean.contract_revision
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  c.id,
  c.uuid_recurrence,
  c.status,
  c.current_revision,
  cr.country,
  cr.contract_version,
  cr.guarantee,
  cr.rental_administrator,
  cr.landlord_legal_person,
  cr.landlord_transfer_funds_day,
  cr.condominium_amount,
  cr.home_insurance_amount,
  cr.brokerage_fee,
  cr.tenant_service_fee,
  cr.admin_fee,
  cr.brokerage_based_fee,
  cr.min_admin_fee,
  CAST(cr.last_rental AS DECIMAL(10, 2)) AS last_rental,
  CAST(cr.last_iptu AS DECIMAL(10, 2)) AS last_iptu,
  cr.is_rental_paid_in_advance,
  cr.ts_signature,
  cr.ts_charge_started,
  cr.ts_charge_ended,
  cr.ts_start_period,
  cr.ts_end_period,
  c.ts_created,
  c.ts_updated,
  NOW() AS ts_load
FROM datalake_billing_clean.contract AS c
LEFT JOIN contract_revision AS cr
  ON c.id = cr.id_contract
