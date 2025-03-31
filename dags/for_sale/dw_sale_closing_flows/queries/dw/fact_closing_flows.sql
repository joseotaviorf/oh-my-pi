SELECT
  id_offer AS sk_offer,
  id_buyer AS sk_buyer,
  id_owner AS sk_owner,
  id_house AS sk_house,
  COALESCE(cs_supply.sk_company, -1) AS sk_company_supply,
  COALESCE(cs_demand.sk_company, -1) AS sk_company_demand,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_sale_agreement_created,1, 10),'-','') AS BIGINT), -1) AS sk_sale_agreement_created_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_sale_agreement_signed,1, 10),'-','') AS BIGINT), -1) AS sk_sale_agreement_signed_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_onboarding_ended,1, 10),'-','') AS BIGINT), -1) AS sk_onboarding_ended_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_sale_agreement_cancelled,1, 10),'-','') AS BIGINT), -1) AS sk_sale_agreement_cancelled_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_sale_agreement_rescued,1, 10),'-','') AS BIGINT), -1) AS sk_sale_agreement_rescued_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_legal_analysis_ended,1, 10),'-','') AS BIGINT), -1) AS sk_legal_analysis_ended_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_legaut_analysis_started,1, 10),'-','') AS BIGINT), -1) AS sk_legaut_analysis_started_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_legaut_analysis_ended,1, 10),'-','') AS BIGINT), -1) AS sk_legaut_analysis_ended_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_legal_risk_started,1, 10),'-','') AS BIGINT), -1) AS sk_legal_risk_started_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_legal_risk_ended,1, 10),'-','') AS BIGINT), -1) AS sk_legal_risk_ended_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_bank_legal_analysis_started,1, 10),'-','') AS BIGINT), -1) AS sk_bank_legal_analysis_started,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_credit_analysis_started,1, 10),'-','') AS BIGINT), -1) AS sk_credit_analysis_started_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_credit_analysis_ended,1, 10),'-','') AS BIGINT), -1) AS sk_credit_analysis_ended_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_financing_started,1, 10),'-','') AS BIGINT), -1) AS sk_financing_started_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_financing_ended,1, 10),'-','') AS BIGINT), -1) AS sk_financing_ended_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_notes_registry_started,1, 10),'-','') AS BIGINT), -1) AS sk_notes_registry_started_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_notes_registry_ended,1, 10),'-','') AS BIGINT), -1) AS sk_notes_registry_ended_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_house_registry_started,1, 10),'-','') AS BIGINT), -1) AS sk_house_registry_started_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_house_registry_ended,1, 10),'-','') AS BIGINT), -1) AS sk_house_registry_ended_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_sale_key_delivered,1, 10),'-','') AS BIGINT), -1) AS sk_sale_key_delivered_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_sale_transacton_paid,1, 10),'-','') AS BIGINT), -1) AS sk_sale_transaction_paid_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_payment_allowed,1, 10),'-','') AS BIGINT), -1) AS sk_payment_allowed_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_down_payment,1, 10),'-','') AS BIGINT), -1) AS sk_down_payment_date,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_diligence_buyer_sent_at,1, 10),'-','') AS BIGINT), -1) AS sk_diligence_buyer_sent_at,
  COALESCE(CAST(REPLACE(SUBSTRING(dt_diligence_seller_sent_at,1, 10),'-','') AS BIGINT), -1) AS sk_diligence_seller_sent_at,
  --
  id_closing_specialist,
  id_legal_risk_analyst,
  id_pre_specialist,
  id_post_specialist,
  id_start_financing_specialist,
  id_follow_up_financing_specialist,
  id_end_financing_specialist,
  id_credit_specialist,
  id_notes_registry_specialist,
  id_real_estate_register_specialist,
  --
  days_sale_agreement_created_to_legaut_analysis_started,
  days_sale_agreement_signed_to_house_registry_started,
  days_sale_agreement_signed_to_house_registry_ended,
  days_sale_agreement_signed_to_sale_agreement_cancelled,
  days_sale_agreement_signed_to_onboarding_ended,
  days_sale_agreement_signed_to_credit_analysis_started,
  days_sale_agreement_signed_to_credit_analysis_ended,
  days_sale_agreement_signed_to_financing_started,
  days_sale_agreement_signed_to_financing_ended,
  days_sale_agreement_signed_to_notes_registry_started,
  days_sale_agreement_signed_to_notes_registry_ended,
  days_sale_agreement_signed_to_legaut_analysis_started,
  days_sale_agreement_signed_to_legaut_analysis_ended,
  days_sale_agreement_signed_to_legal_risk_ended,
  days_sale_agreement_signed_to_bank_legal_analysis_started,
  days_sale_agreement_signed_to_legal_analysis_ended,
  days_legal_risk_started_to_legal_risk_ended,
  days_legal_risk_ended_to_legal_analysis_ended,
  days_legaut_analysis_started_to_legaut_analysis_ended,
  days_legaut_analysis_ended_to_legal_risk_ended,
  days_legal_analysis_ended_notes_registry_ended,
  days_legal_analysis_ended_to_bank_legal_analysis_started,
  days_bank_legal_analysis_started_to_financing_ended,
  days_bank_legal_analysis_started_to_house_registry_started,
  days_credit_analysis_started_to_credit_analysis_ended,
  days_credit_analysis_ended_to_bank_legal_analysis_started,
  days_credit_analysis_ended_to_financing_started,
  days_financing_started_to_bank_legal_analysis_started,
  days_financing_started_to_financing_ended,
  days_financing_ended_to_house_registry_ended,
  days_financing_ended_to_house_registry_started,
  days_notes_registry_started_to_notes_registry_ended,
  days_house_registry_started_to_house_registry_ended,
  days_notes_registry_ended_to_house_registry_started,
  days_notes_registry_ended_to_house_registry_ended,
  days_house_registry_ended_to_sale_key_delivered,
  days_house_registry_ended_to_sale_transaction_paid,
  --
  cf.ts_updated,
  ts_load AS ts_monday_load,
  NOW() AS ts_load
FROM
    datalake_sale_closing_flows.closing_flow AS cf
LEFT JOIN
  datalake_company.company_sks AS cs_demand
    ON (cf.id_company_demand IS NOT NULL
    AND cf.id_company_demand = cs_demand.id_hubspot)
    OR (cf.id_company_demand IS NULL
    AND cf.partner_3p_demand = cs_demand.extracted_3p_tag)
LEFT JOIN
  datalake_company.company_sks AS cs_supply
    ON (
      cf.uuid_company_supply IS NOT NULL
      AND cf.uuid_company_supply = cs_supply.uuid_company
    ) OR (
      cf.uuid_company_supply IS NULL
      AND cf.id_company_supply IS NOT NULL
      AND cf.id_company_supply = cs_supply.id_hubspot
    ) OR (
       cf.uuid_company_supply IS NULL
       AND cf.id_company_supply IS NULL
       AND cf.partner_3p_supply = cs_supply.extracted_3p_tag
    )