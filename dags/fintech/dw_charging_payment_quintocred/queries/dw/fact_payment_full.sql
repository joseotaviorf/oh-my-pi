WITH base_nf_cancellation (
  SELECT 
    id_business_entity AS sk_propose,
    id_finance_entity AS id_finance_entity_cancellation,
    id_document AS id_document_cancellation,
    debit AS value_cancellation,
    CAST( date_trunc( 'MONTH', dt_due ) AS DATE ) AS accrual_year_month_cancellation
  FROM 
    datalake_accounting_funnel.ledger
  WHERE 
    account_number IN ( '31101.07.07', '31102.01.02' ) 
    AND LOWER(comments) LIKE '%cancellation%' 
    AND debit > 0
),
nf_cancellation AS (
  SELECT
    *
  FROM 
    dw_charging_payment_quintocred.fact_accounting_funnel acc
  INNER JOIN
    base_nf_cancellation c
    ON  acc.id_business_entity = c.sk_propose
    AND acc.id_document = c.id_document_cancellation
),
agg_nf_cancellation AS (
  SELECT
    sk_propose,
    accrual_year_month,
    array_join( array_agg( id_document_cancellation ), ',' ) AS id_array_document_canceled,
    COUNT( DISTINCT id_document ) AS qtd_nf_canceled,
    SUM( value_cancellation ) AS total_value_cancellation
  FROM 
    nf_cancellation
  GROUP BY 1,2
),
base_agg_sap_nf AS (
  SELECT
    id_business_entity AS sk_propose,
    accrual_year_month AS year_month_nf,
    COUNT(id_finance_entity) AS qty_total,
    COUNT(hash) AS qty_success,
    SUM(sap_amount) AS sap_amount
  FROM
    dw_charging_payment_quintocred.fact_accounting_funnel
  GROUP BY 1,2
),
agg_sap_nf AS (
  SELECT 
    *,
    CASE
      WHEN qty_success > 1 
        THEN 'FATURAMENTO DUPLICADO'
      WHEN qty_success = 1 
        THEN 'SINGLE FATURAMENTO'
      WHEN qty_success = 0 
        THEN 'SEM FATURAMENTO'
      ELSE 'UNDEFINED'
    END AS sap_class
  FROM 
    base_agg_sap_nf
),
sap_nf AS (
  SELECT 
      agg.sk_propose,
      agg.year_month_nf,
      acc.id_document,
      acc.hash,
      agg.qty_total,
      agg.qty_success,
      agg.sap_amount,
      agg.sap_class
  FROM 
    agg_sap_nf agg
  INNER JOIN 
    dw_charging_payment_quintocred.fact_accounting_funnel acc
    ON acc.id_business_entity = agg.sk_propose
    AND acc.accrual_year_month = agg.year_month_nf
    AND rn_nf = 1
),
level_a AS (
  SELECT
    COALESCE( COALESCE( base.sk_propose_theoretical, base.sk_propose_charge ), sap_nf.sk_propose ) AS sk_propose,
    DATE( COALESCE( COALESCE( base.month_propose_life, base.month_charge ), sap_nf.year_month_nf ) ) AS month,
    base.*,
    CASE
      WHEN mob_of_life IS NULL 
        THEN 'A1'
      WHEN mob_of_life IS NOT NULL 
      AND mob_of_death IS NOT NULL  
      AND day( dt_contract_started ) + 5 >= day( dt_ended ) 
        THEN 'A3'
      WHEN mob_of_life IS NOT NULL  
        THEN 'A2'
    END AS LEVEL_A,
    sap_nf.sk_propose AS sk_propose_nf,
    sap_nf.year_month_nf,
    sap_nf.id_document,
    sap_nf.hash,
    sap_nf.qty_total,
    sap_nf.qty_success,
    sap_nf.sap_amount,
    sap_nf.sap_class,
    IF(
      sap_nf.sap_class IS NULL, 
      'SEM FATURAMENTO - NO ATTEMPT',
      sap_nf.sap_class
    ) AS SAP_CLASS_LEVEL_A,
    IF(
      sap_nf.sap_class IS NULL,
      'SEM FATURAMENTO ',
      sap_nf.sap_class
    ) AS SAP_CLASS_LEVEL_A2
  FROM 
    dw_charging_payment_quintocred.fact_theoretical_payment_delinquency base
  FULL OUTER JOIN 
    sap_nf
    ON COALESCE( sk_propose_theoretical, sk_propose_charge ) = sap_nf.sk_propose
    AND DATE( COALESCE( month_propose_life, month_charge) ) = sap_nf.year_month_nf
),
level_b AS (
  SELECT 
    b.*,
    CASE 
      WHEN level_a = 'A2' 
      AND sk_transaction IS NULL 
        THEN 'B1'
      WHEN level_a = 'A2' 
      AND sk_transaction IS NOT NULL 
        THEN 'B2'
      WHEN level_a = 'A1' 
      AND ( gateway_final IN ( 'ANNUAL_CREDIT_CARD', 'DELINQUENCY_RENEWAL', 'PIXAR', 'ASAAS Anual' ) OR gateway_final IS NULL ) 
        THEN 'B3'
      WHEN level_a = 'A1' 
      AND gateway_final NOT IN ( 'ANNUAL_CREDIT_CARD', 'DELINQUENCY_RENEWAL', 'PIXAR', 'ASAAS Anual' ) 
        THEN 'B4'
      WHEN level_a = 'A3' 
      AND gateway_final IN ( 'ANNUAL_CREDIT_CARD', 'DELINQUENCY_RENEWAL', 'PIXAR', 'ASAAS Anual' ) 
        THEN 'B5'
      WHEN level_a = 'A3' 
      AND gateway_final IN ( 'vivendo de graça' ) 
        THEN 'B6'
      WHEN level_a = 'A3' 
      AND gateway_final NOT IN ( 'ANNUAL_CREDIT_CARD', 'DELINQUENCY_RENEWAL', 'PIXAR', 'ASAAS Anual' ) 
        THEN 'B4'
    END AS LEVEL_B,
    CASE
      WHEN SAP_CLASS_LEVEL_A = 'SINGLE FATURAMENTO' 
      AND ABS( ABS( CAST( sap_amount AS DECIMAL(18,2) ) ) - CAST( pv.monthly_guarantee AS DECIMAL(18,2) ) ) > 0.5 
        THEN 'SINGLE FATURAMENTO - MISMATCH VALUES'
      WHEN SAP_CLASS_LEVEL_A = 'SINGLE FATURAMENTO' 
      AND ( ABS( ABS( CAST( sap_amount AS DECIMAL(18,2) ) ) - cast( pv.monthly_guarantee AS DECIMAL(18,2) ) ) <= 0.5 
      OR sap_amount IS NULL) 
        THEN 'SINGLE FATURAMENTO - SUCESS VALUES'
      ELSE SAP_CLASS_LEVEL_A
    END AS SAP_CLASS_LEVEL_B,
    canc.id_array_document_canceled,
    canc.qtd_nf_canceled,
    canc.total_value_cancellation,
    IF(
      canc.qtd_nf_canceled > 0,
      TRUE,
      FALSE
    ) AS is_nf_canceled,
    IF(
      canc.qtd_nf_canceled > 0, 
      TRUE, 
      FALSE
    ) AS is_cancelled_num
  FROM 
    level_a b
  LEFT JOIN 
    agg_nf_cancellation canc
    ON canc.sk_propose = b.sk_propose_nf
    AND canc.accrual_year_month = b.year_month_nf
  LEFT JOIN 
    dw_velo.fact_velo_propose p
    ON b.sk_propose = p.sk_propose
  LEFT JOIN  
    dw_velo.dim_velo_propose_values pv
    ON pv.sk_propose_values = p.sk_propose_values
),
level_c AS (
  SELECT 
    *,
    CASE 
      WHEN level_b = 'B2' 
      AND value_paid IS NOT NULL 
        THEN 'C1'
      WHEN level_b = 'B2' 
      AND value_paid IS NULL 
        THEN 'C2'
      WHEN level_b = 'B1' 
      AND total_amount_delinquency IS NULL 
        THEN 'C3'
      WHEN level_b = 'B1' 
      AND total_amount_delinquency IS NOT NULL 
        THEN 'C4'
      WHEN level_b = 'B4' 
      AND total_amount_delinquency IS NULL 
      AND value_paid IS NOT NULL 
        THEN 'C7'
      WHEN level_b = 'B4' 
      AND total_amount_delinquency IS NULL 
      AND value_paid IS NULL 
      AND gateway_final = 'BILLING DIRETO' 
        THEN 'C8'
      WHEN level_b = 'B4' 
      AND total_amount_delinquency IS NULL 
      AND value_paid IS NULL 
      AND gateway_final NOT IN ( 'BILLING DIRETO' ) 
        THEN 'C6'
      WHEN level_b = 'B4' 
      AND total_amount_delinquency IS NOT NULL 
        THEN 'C5'
      ELSE 'UNDEFINED'
    END AS LEVEL_C
  FROM level_b
),
level_d AS (
  SELECT 
    *,
    CASE
      WHEN level_c = 'C2' 
      AND sk_delinquency IS NULL 
        THEN 'D1'
      WHEN level_c = 'C2' 
      AND sk_delinquency IS NOT NULL 
        THEN 'D2'
      WHEN level_c = 'C4' 
      AND open_amount_delinquency > 0 
        THEN 'D3'
      WHEN level_c = 'C4' 
      AND open_amount_delinquency <= 0 
        THEN 'D4'
      WHEN level_c = 'C5' 
      AND open_amount_delinquency >0 
        THEN 'D5'
      WHEN level_c = 'C5' 
      AND open_amount_delinquency <=0 
        THEN 'D6'
      WHEN level_c = 'C1' 
      AND total_amount_delinquency IS NULL 
        THEN 'D7'
      WHEN level_c = 'C1' 
      AND total_amount_delinquency IS NOT NULL 
        THEN 'D8'
      ELSE 'UNDEFINED'
    END AS LEVEL_D
  FROM 
    level_c
),
level_e AS (
  SELECT 
    *,
    CASE
      WHEN level_d = 'D2' 
      AND open_amount_delinquency <=0 
        THEN 'E1'
      WHEN level_d = 'D2' 
      AND open_amount_delinquency >0 
      AND is_delinquency_active 
        THEN 'E2'
      WHEN level_d = 'D2' 
      AND open_amount_delinquency >0 
      AND is_delinquency_active = FALSE
        THEN 'E7'
      WHEN level_d = 'D1'
      AND gateway_final = 'BILLING DIRETO' 
        THEN 'E3'
      WHEN level_d = 'D1' 
      AND gateway_final = 'ASAAS RAW' 
      AND status_payment = 'OVERDUE' 
        THEN 'E4'
      WHEN level_d = 'D1'
      AND status_payment IN ( 'REFUSED', 'EXPIRED' ) 
        THEN 'E5'
      WHEN level_d = 'D1' 
      AND (status_payment NOT IN ( 'REFUSED', 'EXPIRED' ) OR status_payment IS NULL) 
        THEN 'E6'
      ELSE 'UNDEFINED'
    END AS LEVEL_E
  FROM
    level_d
),
motivo_expandido AS (
  SELECT *,
    CASE
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B1' 
      AND LEVEL_C = 'C4' 
      AND LEVEL_D = 'D3' 
        THEN 'Cobertura de Pagamento Inadimplente'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B1' 
      AND LEVEL_C = 'C3' 
        THEN 'Vivendo de Graça'
      WHEN LEVEL_A = 'A1' 
      AND LEVEL_B = 'B3' 
        THEN 'TBD - Cobrança Extendida'
      WHEN LEVEL_A = 'A3' 
      AND LEVEL_B = 'B5' 
        THEN 'TBD - Cobrança Extendida'
      WHEN LEVEL_A = 'A3' 
      AND LEVEL_B = 'B6' 
        THEN 'TBD - Vivendo de Graça'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C2' 
      AND LEVEL_D = 'D1' 
      AND LEVEL_E = 'E5' 
        THEN 'Deliquency não emitida -  Status Regular'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C2' 
      AND LEVEL_D = 'D2' 
      AND LEVEL_E = 'E1' 
        THEN 'Bad Debt emitida e Paga'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B1' 
      AND LEVEL_C = 'C4' 
      AND LEVEL_D = 'D4' 
        THEN 'Cobertura de Pagamento Adimplente'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C1' 
      AND LEVEL_D = 'D7' 
        THEN 'Cobrança Paga com Sucesso'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C1' 
      AND LEVEL_D = 'D8' 
        THEN 'Cobrança Paga com Bad Debt Indevida'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C2' 
      AND LEVEL_D = 'D2' 
      AND LEVEL_E = 'E2' 
        THEN 'Bad Debt emitida e Inadimplente'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C2' 
      AND LEVEL_D = 'D2' 
      AND LEVEL_E = 'E7' 
        THEN 'Bad Debt emitida e Arquivada'
      WHEN LEVEL_A = 'A1' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C5' 
      AND LEVEL_D = 'D5' 
        THEN 'Bad Debt Indevida - Contrato ja Finalizado'
      WHEN LEVEL_A = 'A3' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C5' 
      AND LEVEL_D = 'D5' 
        THEN 'Bad Debt Indevida - Finalizacao no mês'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C2' 
      AND LEVEL_D = 'D1' 
      AND LEVEL_E =  'E3' 
        THEN 'Bad Debt de Billing Direto'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C2' 
      AND LEVEL_D = 'D1' 
      AND LEVEL_E =  'E6' 
        THEN 'Deliquency não emitida - Status Ambíguo'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C2' 
      AND LEVEL_D = 'D1' 
      AND LEVEL_E =  'E4' 
        THEN 'Deliquency não emitida - ASAAS Sync'
      WHEN LEVEL_A = 'A1' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C6' 
        THEN 'Cobrança Indevida sem Delinquency'
      WHEN LEVEL_A = 'A3' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C6' 
        THEN 'Cobrança Indevida sem Delinquency'
      WHEN LEVEL_A = 'A1' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C8' 
        THEN 'Cobrança Indevida sem Delinquency - Billing Direto'
      WHEN LEVEL_A = 'A3' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C8' 
        THEN 'Cobrança Indevida sem Delinquency - Billing Direto'
      WHEN LEVEL_A = 'A1' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C7' 
        THEN 'Receita Indevida - Cobrança Mensal Paga - Contrato ja finalizado'
      WHEN LEVEL_A = 'A3' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C7' 
        THEN 'Receita Indevida - Cobrança Mensal Paga - Finalizacao no mês'
      WHEN LEVEL_A = 'A1' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C5' 
      AND LEVEL_D = 'D6' 
        THEN 'Receita Indevida - Deliquency Mensal Paga - Contrato ja finalizado'
      WHEN LEVEL_A = 'A3' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C5' 
      AND LEVEL_D = 'D6' 
        THEN 'Receita Indevida - Deliquency Mensal Paga - Finalizacao no mês'
    END AS motivo_expandido,
    CASE
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B1' 
      AND LEVEL_C = 'C4' 
      AND LEVEL_D = 'D3' 
        THEN '<BD> Payment Coverage Emitted and UNPAID'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B1' 
      AND LEVEL_C = 'C3' 
        THEN '<E> Living for Free - Uncharged and Uncovered'
      WHEN LEVEL_A = 'A1' 
      AND LEVEL_B = 'B3' 
        THEN 'DISMISS'
      WHEN LEVEL_A = 'A3' 
      AND LEVEL_B = 'B5' 
        THEN 'DISMISS'
      WHEN LEVEL_A = 'A3' 
      AND LEVEL_B = 'B6' 
        THEN 'DISMISS'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C2' 
      AND LEVEL_D = 'D1' 
      AND LEVEL_E = 'E5' 
        THEN '<E> Deliquency not emiited - Regular Status'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C2' 
      AND LEVEL_D = 'D2' 
      AND LEVEL_E = 'E1' 
        THEN '<S> New Bad Debt PAID'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B1' 
      AND LEVEL_C = 'C4' 
      AND LEVEL_D = 'D4' 
        THEN '<S> Payment Coverage Emitted and PAID'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C1' 
      AND LEVEL_D = 'D7' 
        THEN '<S> Charge Paid Clear'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C1' 
      AND LEVEL_D = 'D8' 
        THEN '<BD> Charge Paid w/ Wrongful Bad Debt'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C2' 
      AND LEVEL_D = 'D2' 
      AND LEVEL_E = 'E2' 
        THEN '<BD> New Bad Debt UNPAID and Active'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C2' 
      AND LEVEL_D = 'D2' 
      AND LEVEL_E = 'E7' 
        THEN '<F> New Bad Debt Archived'
      WHEN LEVEL_A = 'A1' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C5' 
      AND LEVEL_D = 'D5' 
        THEN '<BD> Wrongful Bad Debt'
      WHEN LEVEL_A = 'A3' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C5' 
      AND LEVEL_D = 'D5' 
        THEN '<BD> Wrongful Bad Debt'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C2' 
      AND LEVEL_D = 'D1' 
      AND LEVEL_E =  'E3' 
        THEN '<BD> Bad Debt from Direct Billing'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C2' 
      AND LEVEL_D = 'D1' 
      AND LEVEL_E =  'E6' 
        THEN 'Deliquency not emiited - Ambiguos Status'
      WHEN LEVEL_A = 'A2' 
      AND LEVEL_B = 'B2' 
      AND LEVEL_C = 'C2' 
      AND LEVEL_D = 'D1' 
      AND LEVEL_E =  'E4' 
        THEN 'Deliquency not emiited - ASAAS SYNC'
      WHEN LEVEL_A = 'A1' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C6' 
        THEN 'Wrongful Unpaid Charge without Deliquency'
      WHEN LEVEL_A = 'A3' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C6' 
        THEN 'Wrongful Unpaid Charge without Deliquency'
      WHEN LEVEL_A = 'A1' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C8' 
        THEN 'Wrongful Unpaid Charge without Deliquency - Billing Direto'
      WHEN LEVEL_A = 'A3' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C8' 
        THEN 'Wrongful Unpaid Charge without Deliquency - Billing Direto'
      WHEN LEVEL_A = 'A1' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C7' 
        THEN 'Wrongful Revenue'
      WHEN LEVEL_A = 'A3' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C7' 
        THEN 'Wrongful Revenue'
      WHEN LEVEL_A = 'A1' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C5' 
      AND LEVEL_D = 'D6' 
        THEN 'Wrongful Revenue'
      WHEN LEVEL_A = 'A3' 
      AND LEVEL_B = 'B4' 
      AND LEVEL_C = 'C5' 
      AND LEVEL_D = 'D6' 
        THEN 'Wrongful Revenue'
    END AS reason_expanded
  FROM 
    level_e
),
bd_not_living_free AS (
SELECT DISTINCT
  sk_propose,
  month
FROM 
  motivo_expandido
WHERE 
  is_direct_billing 
  AND day( dt_contract_started ) BETWEEN 25 AND 31
  AND month_propose_life = add_months( date_trunc( 'MONTH', dt_contract_started ), 1 )
  AND motivo_expandido IN ('Vivendo de Graça')
  AND sk_propose > 5000000
)
SELECT DISTINCT
  m.sk_propose,
  sk_propose_theoretical,
  sk_propose_charge,
  sk_propose_payment,
  sk_transaction,
  sk_delinquency,
  sk_array_delinquency,
  sk_propose_nf,
  sk_propose_delinquency,
  id_document,
  id_array_document_canceled,
  gateway_final,
  LEVEL_A,
  LEVEL_B,
  LEVEL_C,
  LEVEL_D,
  LEVEL_E,
  motivo_expandido AS reason,
  reason_expanded,
  status_at_ref,
  mob_of_life,
  mob_of_death,
  status_payment,
  gateway_payment,
  billing_type_payment,
  status_delinquency,
  gateway_delinquency,
  hash,
  sap_class,
  SAP_CLASS_LEVEL_A,
  SAP_CLASS_LEVEL_A2,
  SAP_CLASS_LEVEL_B,
  monthly_timeline_renewal,
  monthly_timeline_propose_aud,
  monthly_value_propose,
  annual_timeline_renewal,
  annual_timeline_propose_aud,
  annual_value_propose,
  value,
  value_paid,
  total_amount_delinquency,
  delinquency_monthly_value,
  delinquency_amount_paid_monthly,
  total_paid_delinquency,
  open_amount_delinquency,
  total_open_amount_delinquency,
  discount_value_delinquency,
  total_discount_value_delinquency,
  qty_total,
  qty_success,
  qtd_nf_canceled AS qty_nf_canceled,
  total_value_cancellation,
  sap_amount,
  is_nf_canceled,
  is_cancelled_num,
  IF(not_lf.sk_propose IS NOT NULL,
    TRUE,
    FALSE
  ) AS is_free_living,
  CASE 
    WHEN reason_expanded = 'DISMISS' 
    AND SAP_CLASS_LEVEL_B IN ( 'SEM FATURAMENTO', 'SEM FATURAMENTO - NO ATTEMPT' ) 
      THEN TRUE 
    ELSE FALSE 
  END AS is_ignore_dismiss,
  is_charged_on_contract_period,
  is_payment_charge_correct_amount,
  is_retroactive_charging,
  is_overdue,
  is_delinquency_active,
  is_delinquency_charge_related,
  m.month,
  month_propose_life,
  month_chargeble,
  month_charge,
  month_due_original,
  month_delinquency_due,
  year_month_nf
  dt_contract_started,
  dt_ended,
  dt_created_payment,
  dt_due_payment,
  dt_paid_payment,
  dt_paid_delinquency
FROM 
  motivo_expandido m
LEFT JOIN 
  bd_not_living_free not_lf
  ON m.sk_propose = not_lf.sk_propose
  AND m.month = not_lf.month
  ORDER BY sk_propose, month
