SELECT DISTINCT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
  c.id AS sk_contract,
  c.id AS id_contract,
  c.country_code,
  CAST(c.rent AS DECIMAL(14, 2)) AS rent,
  CAST(c.first_rent_charged AS DECIMAL(14, 2)) AS first_rent_charged,
  CAST(c.billing_day_of_month AS SMALLINT) AS day_month_due,
  c.guarantee_type AS guarantee,
  c.type,
  c.status,
  c.rental_administrator,
  c.paying_condo AS condo_payer,
  c.responsible_for_condo AS condo_responsible,
  c.paying_iptu AS iptu_payer,
  c.responsible_for_iptu AS iptu_responsible,
  CAST(c.rental_guarantee_installment AS SMALLINT) AS rental_insurance_installments,
  CAST(c.rental_guarantee_value AS  DECIMAL(14, 2)) AS rental_insurance_value,
  CAST(c.home_insurance_installment AS SMALLINT) AS home_insurance_installments,
  CAST(c.home_insurance_value AS DECIMAL(14, 2)) AS home_insurance_value,
  CAST(c.fist_rent_comission_fee AS DECIMAL(14, 2)) AS first_rental_commission,
  CAST(c.monthly_administration_fee AS DECIMAL(5, 4)) AS monthly_administration_fee,
  CAST(c.condo_price AS DECIMAL(14, 2)) AS condo,
  CAST(c.iptu AS DECIMAL(14, 2)) AS iptu,
  CAST(c.tenant_service_fee AS DECIMAL(5, 4)) AS tenant_service_fee,
  CAST(c.agent_brokerage_share AS DECIMAL(5, 3)) AS agent_brokerage_share,
  c.signature_type,
  c.status_closing AS closing_status,
  c.cancellation_reason,
  c.contract_version AS version,
  b2b.is_b2b OR contract_b2b.is_b2b AS is_b2b,
  contract_b2b.is_contract_b2b,
  contract_b2b.contract_partner_type,
  contract_b2b.b2b_type,
  contract_b2b.b2b_prime_type,
  contract_b2b.contract_plan,
  c.value_segment,
  CAST(contract_b2b.administration_split_percentage AS DECIMAL(5, 3)) AS administration_split_percentage,
  CAST(contract_b2b.brokerage_split_percentage AS DECIMAL(5, 3)) AS brokerage_split_percentage,
  c.is_ongoing_contract,
  c.is_tenant_service_fee_opt_out,
  c.is_exit_inspection_opted_out,
  ct.is_repair_tenant_duty,
  ca.is_anomaly,
  c.dt_started AS dt_start,
  c.dt_entered AS dt_entrance,
  c.dt_contract_expected_end AS dt_intended_end,
  c.dt_termination AS dt_annulment,
  ct.ts_created AS ts_termination_requested,
  c.ts_created,
  c.ts_updated,
  c.ts_expected_termination,
  c.ts_signed AS ts_signature,
  c.ts_minuta_approved AS ts_draft_approved,
  CAST(c.ts_canceled AS TIMESTAMP) AS ts_canceled,
  c.ts_tenant_service_fee_opt_out,
  CAST(c.ts_analyst_annulment_input AS TIMESTAMP) AS ts_analyst_annulment_input,
  DATE(COALESCE(c.ts_analyst_annulment_input,c.dt_termination)) AS dt_ended_rental_confirmed,
  NOW() AS ts_load
FROM
    datalake_ebdb_contract.contract c
LEFT JOIN
    datalake_ebdb_contract.contract_b2b contract_b2b
        ON contract_b2b.id_contract = c.id
LEFT JOIN 
    datalake_b2b.house_listing b2b
      ON b2b.id_contract = c.id
LEFT JOIN
    datalake_offboarding.contract_termination AS ct
      ON ct.id_contract = c.id
        AND ct.status <> 'CANCELED'
LEFT JOIN
    datalake_offboarding.contract_anomaly AS ca
      ON ca.id_contract = c.id