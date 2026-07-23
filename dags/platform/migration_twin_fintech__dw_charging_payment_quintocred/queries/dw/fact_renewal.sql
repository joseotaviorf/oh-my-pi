WITH 
get_dt_paid_renewal AS (
  SELECT
    CASE  
      WHEN DATE_TRUNC('MONTH', dt_due_renewal_coalesce) > DATE_TRUNC('MONTH', dt_ended_official) THEN 'x1. ENDED BEFORE MONTH OF RENEWAL'
      WHEN DATE_TRUNC('MONTH', dt_due_renewal_coalesce) = DATE_TRUNC('MONTH', dt_ended_official) THEN 'x2. ENDED IN MONTH OF RENEWAL'
      WHEN dt_due_renewal_coalesce >= (current_date - INTERVAL '1' day) OR (dt_due_renewal_coalesce IS NULL AND dt_expected_day_renewal >= (current_date - INTERVAL '1' day)) THEN 'xx. FUTURE RENEWAL'
      ELSE 'TBD' 
    END AS status_renewal_proposal,
    ARRAY_MAX(
      FILTER(
        FLATTEN(dt_arr_paid_valid),
        x -> x IS NOT NULL
      )
    ) AS max_paid_dt,
    ARRAY_MAX(
      FILTER(
        FLATTEN(id_arr_type_valid),
        x -> x IS NOT NULL
      )
    ) AS max_id_type,
    *
  FROM 
    dw_charging_payment_quintocred.fact_renewal_base
),
payments_registry AS (
  SELECT 
    month_reference,
    m.reason_expanded_portuguese,
    CAST(m.sk_propose AS BIGINT) AS sk_propose,
    f.billing_mode_at_ref,
    gateway_payment,
    status_payment,
    dt_paid_payment,
    dt_due_payment,
    billing_type_payment,
    sk_transaction,
    f.gateway AS cpts_gateway,
    f.billing_type AS billing_type_cpts,
    f.status AS cpts_status,
    f.id AS id_cpts,
    f.dt_contract_started,
    f.dt_ended
  FROM 
    dw_charging_payment_quintocred.fact_payment_full m
  LEFT JOIN 
    dw_collection_recovery_quintocred.fact_proposal_signature_payment_timeline f 
      ON f.ref_month = m.month_reference 
      AND CAST(f.sk_propose AS BIGINT) = CAST(m.sk_propose AS BIGINT)
  WHERE
    f.renewal_status = 'RENEWAL AT MONTH'
),
get_rule_dt_renewal AS (
  SELECT 
    CASE 
      WHEN m.billing_mode_at_ref = 'BROKER' OR f.gateway_payment = 'BILLING DIRETO' THEN 'FLUXO C - BILLING DIRETO'
      WHEN link_checkout IS NOT NULL OR link_checkout_propose IS NOT NULL THEN 'FLUXO D - NEW CHECKOUT'
      WHEN f.gateway_payment IN ('CREDIT_CARD', 'ANNUAL_CREDIT_CARD', 'PIXAR', 'CHECKOUT_V2') OR (max_id_type = 4) THEN 'FLUXO B - OLD CHECKOUT'
      WHEN (max_id_type = 0) OR f.gateway_payment IN ('ASAAS Anual', 'ASAAS RAW', 'ASAAS', 'IUGU') THEN 'FLUXO A - ASSAS'
      WHEN (max_id_type = -1) THEN 'FLUXO - PROJECT VDG FIX'
      WHEN f.reason_expanded_portuguese = 'Vivendo de Graça' THEN 'FLUXO - VDG IN RENEWAL'
      ELSE 'UNCLEAR FLUX' 
    END AS flux_determination, 
    m.*, 
    f.reason_expanded_portuguese,
    f.gateway_payment,
    f.status_payment,
    f.dt_paid_payment,
    f.dt_due_payment,
    f.billing_type_payment,
    f.sk_transaction,
    f.cpts_gateway,
    f.id_cpts,
    f.cpts_status,
    f.billing_type_cpts
  FROM 
    get_dt_paid_renewal m
  LEFT JOIN 
    payments_registry f 
      ON m.sk_propose_official = f.sk_propose 
      AND f.month_reference = m.ref_month_renewal_coalesce
),
class_building_lvl1 AS (
  SELECT *,
    CASE 
      WHEN flux_determination = 'FLUXO - VDG IN RENEWAL' AND max_id_type IS NULL THEN 'V1'
      WHEN flux_determination = 'FLUXO - VDG IN RENEWAL' AND max_id_type IS NOT NULL THEN 'V2'
      WHEN flux_determination = 'FLUXO A - ASSAS' AND status_payment IN ('SUCCESS', 'RECEIVED') THEN 'A1'
      WHEN flux_determination = 'FLUXO A - ASSAS' AND (NOT(status_payment IN ('SUCCESS', 'RECEIVED')) OR status_payment IS NULL) THEN 'A2'
      WHEN flux_determination = 'FLUXO B - OLD CHECKOUT' AND status_payment IN ('SUCCESS', 'PROCESSING') AND gateway_payment IN ('CREDIT_CARD', 'PIXAR', 'CHECKOUT_V2', 'ANNUAL_CREDIT_CARD') THEN 'B1'
      WHEN flux_determination = 'FLUXO B - OLD CHECKOUT' AND NOT(status_payment IN ('SUCCESS', 'PROCESSING') AND gateway_payment IN ('CREDIT_CARD', 'PIXAR', 'CHECKOUT_V2', 'ANNUAL_CREDIT_CARD')) THEN 'B2'
      WHEN flux_determination = 'FLUXO C - BILLING DIRETO' AND status_payment IN ('OVERDUE') THEN 'C2'
      WHEN flux_determination = 'FLUXO C - BILLING DIRETO' AND status_payment IS NULL THEN 'C3'
      WHEN flux_determination = 'FLUXO C - BILLING DIRETO' AND NOT(status_payment IN ('OVERDUE') OR status_payment IS NULL) THEN 'C1'
      WHEN flux_determination = 'FLUXO D - NEW CHECKOUT' AND renewal_link_status = 'LINK_PAID' THEN 'D1'
      WHEN flux_determination = 'FLUXO D - NEW CHECKOUT' AND partial_link_status = 'LINK_PAID' THEN 'D2'
      WHEN flux_determination = 'FLUXO D - NEW CHECKOUT' AND renewal_link_status = 'LINK_UNPAID' AND partial_link_status = 'LINK_UNPAID' THEN 'D3'
      WHEN flux_determination = 'FLUXO D - NEW CHECKOUT' AND renewal_link_status = 'LINK_UNPAID' AND partial_link_status IS NULL AND dt_due_link_checkout >= (current_date - interval '1' day) THEN 'D4'
      WHEN flux_determination = 'FLUXO D - NEW CHECKOUT' AND ((renewal_link_status = 'LINK_UNPAID' AND partial_link_status IS NULL) OR (renewal_link_status IS NULL AND partial_link_status = 'LINK_UNPAID')) AND (status_payment IN ('SUCCESS') AND gateway_payment IN ('CREDIT_CARD', 'PIXAR', 'CHECKOUT_V2', 'ANNUAL_CREDIT_CARD')) AND ref_month_renewal_coalesce <= date('2024-9-1') THEN 'D5'
      WHEN flux_determination = 'FLUXO D - NEW CHECKOUT' AND ((renewal_link_status = 'LINK_UNPAID' AND partial_link_status IS NULL) OR (renewal_link_status IS NULL AND partial_link_status = 'LINK_UNPAID')) THEN 'D4'
      WHEN flux_determination = 'FLUXO - PROJECT VDG FIX' THEN 'V3'
      ELSE 'LVL 1. UNDEFINED' 
    END AS LVL_1
  FROM get_rule_dt_renewal
),
class_building_lvl2 AS (
  SELECT *,
    CASE 
      WHEN LVL_1 = 'V2' AND max_id_type = -2 THEN 'V21'
      WHEN LVL_1 = 'V2' AND max_id_type = -4 THEN 'V22'
      WHEN LVL_1 = 'A2' AND max_id_type IS NULL THEN 'A21'
      WHEN LVL_1 = 'A2' AND max_id_type >= -1 THEN 'A22'
      WHEN LVL_1 = 'A2' AND max_id_type < -1 THEN 'A23'
      WHEN LVL_1 = 'B2' AND max_id_type IS NULL THEN 'B21'
      WHEN LVL_1 = 'B2' AND max_id_type >= -1 THEN 'B22'
      WHEN LVL_1 = 'B2' AND max_id_type < -1 THEN 'B23'
      WHEN flux_determination = 'FLUXO D - NEW CHECKOUT' AND qtd_delinquencies_total = 0 THEN 'D31'
      WHEN flux_determination = 'FLUXO D - NEW CHECKOUT' AND qtd_delinquencies_total > 0 AND qtd_delinquencies_active_total = 0 THEN 'D32'
      WHEN flux_determination = 'FLUXO D - NEW CHECKOUT' AND qtd_delinquencies_total > 0 AND qtd_delinquencies_active_total > 0 THEN 'D33'
      ELSE LVL_1 
    END AS LVL_2
  FROM class_building_lvl1
),
class_building_lvl3 AS (
  SELECT *,
    CASE 
      WHEN LVL_2 = 'A22' AND (amount_paid_active >= total_amount_active) THEN 'A221'
      WHEN LVL_2 = 'A22' AND (amount_paid_active < total_amount_active) THEN 'A222'
      WHEN LVL_2 = 'B22' AND (amount_paid_active >= total_amount_active) THEN 'B221'
      WHEN LVL_2 = 'B22' AND (amount_paid_active < total_amount_active) THEN 'B222'
      WHEN LVL_2 = 'D33' AND (amount_paid_active_total_annual >= total_amount_active_annual) THEN 'D331'
      WHEN LVL_2 = 'D33' AND (amount_paid_active_total_annual < total_amount_active_annual) THEN 'D332'
      ELSE LVL_2 
    END AS LVL_3
  FROM class_building_lvl2
),
dictionary_bussiness AS (
  SELECT 
    CASE 
      WHEN status_renewal_proposal = 'x1. ENDED BEFORE MONTH OF RENEWAL' THEN '0 - ENDED BEFORE MONTH OF RENEWAL'
      WHEN status_renewal_proposal = 'xx. FUTURE RENEWAL' AND LVL_1 IN ('LVL 1. UNDEFINED', 'V1', 'V2', 'V3', 'D4') THEN '-1 - FUTURE RENEWAL'
      WHEN status_renewal_proposal = 'TBD' AND LVL_3 = 'LVL 1. UNDEFINED' THEN '99 - UNDEFINED'
      WHEN LVL_3 IN ('V1', 'V21', 'V22', 'V3') THEN '98 - RENEWAL ERROR'
      WHEN LVL_3 IN ('C1', 'C2', 'C3') THEN '97 - BILLING DIRETO'
      WHEN status_renewal_proposal = 'TBD' AND LVL_1 IN ('D3', 'D4') AND LVL_3 = 'D331' THEN '96 - ASSINATURA FAKE'
      WHEN LVL_3 IN ('A1', 'B1', 'C1', 'C2', 'C3') OR (LVL_1 IN ('D1', 'D2', 'D5')) OR (LVL_1 = 'D4' AND LVL_3 = 'D331') THEN '1 - RENEWED'
      WHEN LVL_3 IN ('A221', 'B221') THEN '2 - RENEWED AFTER DELINQUENCY'
      WHEN status_renewal_proposal = 'TBD' AND (LVL_3 IN ('A222', 'B222', 'A21', 'B21', 'A23', 'B23') OR (LVL_1 IN ('D3', 'D4'))) THEN '3 - PENDING RENEWAL'
      WHEN status_renewal_proposal = 'x2. ENDED IN MONTH OF RENEWAL' AND (LVL_3 IN ('A222', 'B222', 'A21', 'B21', 'A23', 'B23', 'LVL 1. UNDEFINED', 'V1', 'V21', 'V22', 'V3') OR (LVL_1 IN ('D3','D4', 'LVL 1. UNDEFINED'))) THEN '0 - ENDED AT MONTH OF RENEWAL'
      ELSE '100 - ERROR IN DICTIONARY'
    END AS renewal_dictionary,
    CASE 
      WHEN LVL_3 IN ('A1', 'B1') OR LVL_1 = 'D5' THEN dt_paid_payment
      WHEN LVL_1 IN ('D1', 'D2') THEN COALESCE(dt_paid_link_renewal, dt_paid_link_partial)
      WHEN (LVL_1 = 'D4' AND LVL_3 = 'D331') OR LVL_3 IN ('A221', 'B221') THEN max_paid_dt
      WHEN LVL_3 IN ('C1', 'C2', 'C3') THEN dt_due_renewal_coalesce
      ELSE NULL 
    END AS dt_renewed,
    *
  FROM 
    class_building_lvl3
)

SELECT
  sk_propose_official,  
  sk_transaction,  
  id_imob,  
  id_link_renewal,  
  id_partial_link,  
  id_arr_type_valid,  
  id_arr_delinquency_valid,  
  id_arr_type_valid_active,  
  id_arr_delinquency_valid_active,  
  id_arr_type_archived_valid,  
  id_arr_delinquency_archived_valid,  
  id_arr_type,  
  id_arr_delinquency,  
  id_arr_delinquency_active,  
  id_arr_delinquency_archived,  
  id_cpts,  
  max_id_type AS id_max_type,  
  renewal_dictionary,  
  CASE 
    WHEN renewal_dictionary = '1 - RENEWED' AND date_trunc('month', dt_renewed) <= ref_month_renewal_coalesce THEN '1A - RENEWED MOB0'
    WHEN renewal_dictionary = '1 - RENEWED' AND date_trunc('month', dt_renewed) > ref_month_renewal_coalesce THEN '1A - RENEWED MOB1+'
    ELSE RENEWAL_DICTIONARY 
  END AS renewal_dictionary_lvl2,
  flux_determination,  
  status_renewal_proposal, 
  days_step,  
  price_index_type,  
  payment_method,  
  billing_model_at_renewal,  
  step_from_product,  
  link_checkout,  
  link_checkout_creation,  
  flow_type,  
  link_checkout_propose,  
  link_checkout_creation_propose,  
  flow_type_propose,  
  n_installments_partial_link,  
  name,  
  phone,  
  email,  
  renewal_link_status,  
  partial_link_status,  
  billing_mode_at_ref,  
  reason_expanded_portuguese,  
  gateway_payment,  
  status_payment,  
  billing_type_payment,  
  cpts_gateway,  
  cpts_status,  
  cycle,  
  billing_type_cpts,  
  LVL_1 AS classification_lvl1,  
  LVL_2 AS classification_lvl2,  
  LVL_3 AS classification_lvl3,  
  qtd_delinquencies,  
  total_amount,  
  amount_paid,  
  qtd_delinquencies_active,  
  total_amount_active,  
  amount_paid_active,  
  qtd_delinquencies_archived,  
  total_amount_archived,  
  qtd_delinquencies_total,  
  qtd_delinquencies_active_total,  
  qtd_delinquencies_archived_total,  
  total_amount_active_annual,  
  amount_paid_active_total_annual,  
  previous_amount,  
  current_amount,  
  value_percent,  
  ref_month_renewal_coalesce,  
  year_of_renewal,  
  ref_month_renewal,   
  dt_arr_created_valid,  
  dt_arr_paid_valid,  
  dt_arr_created_valid_active,  
  dt_arr_due_valid_active,  
  dt_arr_created_archived_valid,  
  dt_arr_due_archived_valid,
  max_paid_dt AS dt_max_paid,  
  dt_due_renewal_coalesce,    
  dt_ended_official,  
  dt_due_renewal, 
  dt_paid_renewal,  
  dt_due_link_checkout,  
  dt_due_link_checkout_propose,  
  dt_paid_link_renewal,  
  dt_paid_link_partial,  
  dt_contract_started, 
  dt_paid_payment,  
  dt_due_payment,  
  dt_renewed,
  NOW() AS ts_load
FROM 
  dictionary_bussiness
