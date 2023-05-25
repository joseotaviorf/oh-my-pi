WITH BASE_VENCIMENTOS_PADRONIZADOS AS(
  WITH base_1 AS(
    SELECT 
      accrual_year_month,
      cast(ts_due AS date) AS dt_due,
      count(id_external) AS qtd_faturas 
    FROM 
      datalake_retsuko_clean.invoice
    WHERE 
      purpose = 'monthly' 
      AND due_amount <= 0
    GROUP BY 1,2
  ),
  base_2 AS(
    SELECT 
      *, 
      row_number() OVER(PARTITION BY accrual_year_month ORDER BY qtd_faturas DESC, dt_due DESC) AS rowNumber 
    FROM 
      base_1
  )
  SELECT 
    accrual_year_month, 
    dt_due
  FROM 
    base_2
  WHERE 
    rowNumber = 1
),
BASE_ACORDOS_METODOLOGIA_ANTIGA AS(
  WITH base_acordo_antigo AS(
    SELECT 
      id_invoice_external AS sk_invoice,
      dt_created,
      id_contract_external AS sk_contract,
      accrual_year_month AS accrual_year_month_renegociada,
      description
    FROM 
      (
        SELECT 
          e.*, 
          c.id_external AS id_contract_external, 
          i.id_external AS id_invoice_external, 
          cast(i.ts_created AS date) AS dt_created 
        FROM 
          datalake_retsuko_clean.entry e
        LEFT JOIN 
          datalake_retsuko_clean.contract c 
            ON c.id = e.id_contract
        LEFT JOIN 
          datalake_retsuko_clean.invoice i 
            ON i.id = e.id_invoice
        WHERE
        (trim(upper(e.description)) LIKE '%ACORDO COBRAN%' AND (trim(upper(e.bill_item)) LIKE '%ENTRY.BILL-ITEM/INSURANCE-GUARANTEE%'))
      )
    WHERE 
      id_invoice_external IS NOT NULL
  )
  SELECT 
    baa.sk_contract, 
    baa.sk_invoice AS sk_deal_invoice, 
    baa.dt_created AS dt_created_deal, 
    bvp.dt_due AS dt_min_due_date_at_deal
  FROM 
    base_acordo_antigo AS baa
  LEFT JOIN 
    BASE_VENCIMENTOS_PADRONIZADOS bvp
      ON bvp.accrual_year_month = baa.accrual_year_month_renegociada
),
BASE_ACORDOS_METODOLOGIA_NOVA AS(
  WITH base_de_acordos AS(
    SELECT
      c.id_external AS NuContrato,
      n.id AS Id_Acordo,
      n.status AS Status_Acordo,
      cast(n.ts_created AS date) AS Dt_Criacao_Acordo,
      d.id_external AS Invoice_id_Origem,
      cast(i.ts_due AS date) AS tsdue_Origem,
      i.due_amount AS dueAmount_Origem,
      cast(i.ts_paid AS date) AS tspaid_Origem,
      i.paid_amount
    FROM
      datalake_trato_feito_clean.negotiation n 
    INNER JOIN 
      datalake_trato_feito_clean.debt d                                                     
        ON n.id = d.id_negotiation
    INNER JOIN 
      datalake_retsuko_clean.invoice i                                                      
        ON i.id_external = cast(d.id_external AS bigint)
    INNER JOIN 
      datalake_retsuko_clean.contract c                                                    	
        ON i.id_contract = c.id 
  ), 
  total_parcelas AS(
    SELECT
      a.NuContrato AS sk_contract,
      a.Invoice_id_Origem,
      a.tsdue_Origem,
      a.Dt_Criacao_Acordo AS dt_created_deal,
      ai.id_external AS sk_deal_invoice,
      cast(i.ts_due AS date) AS tsdue_Acordo,
      i.due_amount AS dueAmount_Acordo,
      cast(i.ts_paid AS date) AS tspaid_Acordo,
      i.paid_amount AS paidamount_Acordo  
    FROM  
      base_de_acordos a
    INNER JOIN 
      datalake_trato_feito_clean.installment p  
        ON a.Id_Acordo = p.id_negotiation
    INNER JOIN 
      datalake_trato_feito_clean.accounting_installment ai  
        ON ai.id_installment = p.id
    INNER JOIN 
      datalake_retsuko_clean.invoice i  
        ON i.id_external = cast(ai.id_external AS bigint)
  )
  SELECT
    sk_contract,
    sk_deal_invoice,
    dt_created_deal,
    min(tsdue_origem) as dt_min_due_date_at_deal
  FROM 
    total_parcelas
  GROUP BY 1,2,3
),
BASE_ACORDOS_GLOBAL AS(
  SELECT 
    * 
  FROM 
    BASE_ACORDOS_METODOLOGIA_ANTIGA
  UNION ALL
  SELECT 
    * 
  FROM 
    BASE_ACORDOS_METODOLOGIA_NOVA
),
base_step0_delay AS(
  SELECT 
    fc.*,
    CASE WHEN payment_status = 'paid' AND dt_paid > dt_closing THEN NULL ELSE dt_paid END AS dt_paid_adjs,
    CASE WHEN fc.frequency = 'monthly' THEN v.dt_due ELSE fc.dt_due END AS dt_due_adjs,
    d.dt_created_deal,
    d.dt_min_due_date_at_deal AS deal_anchor_due_date,
    v.dt_due as dt_due_general_accrual
  FROM 
    datalake_losses.closing fc
  LEFT JOIN 
    BASE_ACORDOS_GLOBAL d 
      ON d.sk_deal_invoice = fc.id_invoice
  LEFT JOIN
    BASE_VENCIMENTOS_PADRONIZADOS v 
      ON v.accrual_year_month = fc.accrual_year_month
),
base_step1_delay AS(
  SELECT
    *,
    CASE WHEN deal_anchor_due_date IS NOT NULL THEN 1 ELSE 0 END AS flag_is_invoice_deal,
    datediff(dt_due_adjs, dt_closing) AS delta_days,
    datediff(deal_anchor_due_date, dt_created_deal) AS delay_at_deal_creation,
    datediff(deal_anchor_due_date, dt_closing) AS full_delay_at_deal
  FROM 
    base_step0_delay
),
base_aux_ref_contract_deals AS(
  SELECT 
    DISTINCT id_contract, 
    dt_closing 
  FROM 
    base_step1_delay 
  WHERE 
    flag_is_invoice_deal = 1
),
base_aux_ref_contract_deals_ AS(
  SELECT 
    *, 
    TRUE as flas_contract_has_deal 
  FROM 
    base_aux_ref_contract_deals
),
base_flag_oldest_deal AS(
  SELECT 
    DISTINCT id_contract, 
    dt_closing, 
    id_invoice, 
    row_number() OVER(PARTITION BY id_contract, dt_closing ORDER BY deal_anchor_due_date ASC, dt_created_deal ASC) AS deal_order 
  FROM  
    base_step1_delay 
  WHERE 
    flag_is_invoice_deal = 1
),
base_step2_delay AS(
  SELECT 
    m.*,
    CASE WHEN flag_is_invoice_deal = 1 AND delta_days < 0 THEN 'DEAL IN DELAY'
         WHEN flag_is_invoice_deal = 1 AND delta_days >= 0 THEN 'DEAL ON TIME. DELAY AT ANCHOR'
         WHEN flag_is_invoice_deal = 0 THEN 'NOT-DEAL' 
    END AS flag_deal_status_on_delay,
    coalesce(aux.flas_contract_has_deal, FALSE) AS flas_contract_has_deal,
    deal_age.deal_order AS deal_order
  FROM 
    base_step1_delay m
  LEFT JOIN 
    base_aux_ref_contract_deals_ aux 
      ON (aux.id_contract = m.id_contract) AND (aux.dt_closing = m.dt_closing)
  LEFT JOIN 
    base_flag_oldest_deal deal_age 
      ON (deal_age.id_contract = m.id_contract) AND (deal_age.dt_closing = m.dt_closing) AND (m.id_invoice = deal_age.id_invoice)
),
base_step2_delay_mid AS(
  SELECT 
    m.*,
  -- RULE A: Current on 2022 
  -- Set de delay on the time of the anchor of the deal, doesn`t look if the payment is up to date
    CASE WHEN flag_is_invoice_deal = 1 THEN least(full_delay_at_deal, delta_days) ELSE delta_days END AS deal_delay_rule_A,
  -- RULE B: Verifies if the de delay of the deal invoice is greater than the delay of the deal date, if not it keeps the delay of the deal date
    CASE WHEN flag_is_invoice_deal = 1 AND deal_order=1 THEN least(delta_days, delay_at_deal_creation) ELSE delta_days END AS deal_delay_rule_B,
  -- RULE C: Verifies if the contract has parcels on delay, if not, the delay is set to the moment of the deal, if yes it will use the delay of the anchor.
    CASE WHEN flag_is_invoice_deal = 1 AND flag_deal_status_on_delay = 'DEAL IN DELAY' THEN full_delay_at_deal
         WHEN flag_is_invoice_deal = 1 AND flag_deal_status_on_delay = 'DEAL ON TIME. DELAY AT ANCHOR' THEN delay_at_deal_creation
         WHEN flag_is_invoice_deal = 0 THEN delta_days END AS deal_delay_rule_C,
  -- RULE D: Verifies if the contract has parcels on delay, if not, it will use the delay of the delay of the deal date plus anchor.
    CASE WHEN flag_is_invoice_deal = 1 AND flag_deal_status_on_delay = 'DEAL IN DELAY' THEN delta_days + delay_at_deal_creation
         WHEN flag_is_invoice_deal = 1 AND flag_deal_status_on_delay = 'DEAL ON TIME. DELAY AT ANCHOR' THEN delay_at_deal_creation
         WHEN flag_is_invoice_deal = 0 THEN delta_days END AS deal_delay_rule_D
  FROM 
    base_step2_delay m
),
base_aux_ref_contract_delays AS(
  SELECT
    dt_closing,
    id_contract,
    user,
    min(deal_delay_rule_A) AS delay_contaminated_range_rule_A,
    min(deal_delay_rule_B) AS delay_contaminated_range_rule_B,
    min(deal_delay_rule_C) AS delay_contaminated_range_rule_C,
    min(deal_delay_rule_D) AS delay_contaminated_range_rule_D
  FROM 
    base_step2_delay_mid
  GROUP BY 1,2,3
),
base_aux_ref_contract_risk AS(
  SELECT 
    DISTINCT dt_closing,
    id_contract
  FROM 
    base_step2_delay_mid
  WHERE 
    frequency = 'extra' 
    OR frequency = 'early termination' 
    OR frequency = 'pos rental'
),
base_aux_ref_contract_risk_ AS(
  SELECT 
    *,
    TRUE as flag_is_HR
  FROM 
    base_aux_ref_contract_risk
),
base_step3_delay AS(
  SELECT 
    m.*, 
    aux.delay_contaminated_range_rule_B, 
    aux.delay_contaminated_range_rule_A,  
    aux.delay_contaminated_range_rule_C,  
    aux.delay_contaminated_range_rule_D, 
    aux_hr.flag_is_HR
  FROM base_step2_delay_mid m
  LEFT JOIN 
    base_aux_ref_contract_delays AS aux 
      ON (aux.id_contract = m.id_contract) AND (aux.dt_closing = m.dt_closing) AND (aux.user = m.user)
  LEFT JOIN 
    base_aux_ref_contract_risk_ AS aux_hr 
      ON (aux_hr.id_contract = m.id_contract) AND (aux_hr.dt_closing = m.dt_closing)
),
base_step4_delay AS(
  SELECT 
    *,
    CASE WHEN delay_contaminated_range_rule_A <= -181 THEN 'TotalM +6 (>181 days)'
         WHEN delay_contaminated_range_rule_A <= -151 THEN 'TotalM +5 (151-180 days)'
         WHEN delay_contaminated_range_rule_A <= -121 THEN 'TotalM +4 (121-150 days)'
         WHEN delay_contaminated_range_rule_A <= -91 THEN 'TotalM +3 (91-120 days)'
         WHEN delay_contaminated_range_rule_A <= -61 THEN 'TotalM +2 (61-90 days)'
         WHEN delay_contaminated_range_rule_A <= -31 THEN 'TotalM +1 (31-60 days)'
         WHEN delay_contaminated_range_rule_A <= -1 THEN 'TotalM +0 (1-30 days)'
         ELSE 'TotalCurrent' 
    END AS pd_range_rule_A,
    CASE WHEN delay_contaminated_range_rule_B <= -181 THEN 'TotalM +6 (>181 days)'
         WHEN delay_contaminated_range_rule_B <= -151 THEN 'TotalM +5 (151-180 days)'
         WHEN delay_contaminated_range_rule_B <= -121 THEN 'TotalM +4 (121-150 days)'
         WHEN delay_contaminated_range_rule_B <= -91 THEN 'TotalM +3 (91-120 days)'
         WHEN delay_contaminated_range_rule_B <= -61 THEN 'TotalM +2 (61-90 days)'
         WHEN delay_contaminated_range_rule_B <= -31 THEN 'TotalM +1 (31-60 days)'
         WHEN delay_contaminated_range_rule_B <= -1 THEN 'TotalM +0 (1-30 days)'
         ELSE 'TotalCurrent' 
    END AS pd_range_rule_B,
    CASE WHEN delay_contaminated_range_rule_C <= -181 THEN 'TotalM +6 (>181 days)'
         WHEN delay_contaminated_range_rule_C <= -151 THEN 'TotalM +5 (151-180 days)'
         WHEN delay_contaminated_range_rule_C <= -121 THEN 'TotalM +4 (121-150 days)'
         WHEN delay_contaminated_range_rule_C <= -91 THEN 'TotalM +3 (91-120 days)'
         WHEN delay_contaminated_range_rule_C <= -61 THEN 'TotalM +2 (61-90 days)'
         WHEN delay_contaminated_range_rule_C <= -31 THEN 'TotalM +1 (31-60 days)'
         WHEN delay_contaminated_range_rule_C <= -1 THEN 'TotalM +0 (1-30 days)'
         ELSE 'TotalCurrent' 
    END AS pd_range_rule_C,
    CASE WHEN delay_contaminated_range_rule_D <= -181 THEN 'TotalM +6 (>181 days)'
         WHEN delay_contaminated_range_rule_D <= -151 THEN 'TotalM +5 (151-180 days)'
         WHEN delay_contaminated_range_rule_D <= -121 THEN 'TotalM +4 (121-150 days)'
         WHEN delay_contaminated_range_rule_D <= -91 THEN 'TotalM +3 (91-120 days)'
         WHEN delay_contaminated_range_rule_D <= -61 THEN 'TotalM +2 (61-90 days)'
         WHEN delay_contaminated_range_rule_D <= -31 THEN 'TotalM +1 (31-60 days)'
         WHEN delay_contaminated_range_rule_D <= -1 THEN 'TotalM +0 (1-30 days)'
         ELSE 'TotalCurrent' 
    END AS pd_range_rule_D,
    CASE WHEN flag_is_HR IS TRUE THEN 'HR' 
         ELSE 'LR' 
    END AS flag_risk
  FROM 
    base_step3_delay
)
SELECT 
  id_invoice,
  id_contract,
  accrual_year_month
  deal_delay_rule_A,
  deal_delay_rule_B,
  deal_delay_rule_C,
  deal_delay_rule_D,
  deal_order,
  flag_deal_status_on_delay as deal_status, 
  delay_at_deal_creation,
  delay_contaminated_range_rule_A,
  delay_contaminated_range_rule_B,
  delay_contaminated_range_rule_C,
  delay_contaminated_range_rule_D,
  delta_days,
  due_amount,
  frequency,
  full_delay_at_deal,
  pd_range_rule_A,
  pd_range_rule_B,
  pd_range_rule_C,
  pd_range_rule_D,
  flag_risk as risk_type,
  is_before_started,
  flas_contract_has_deal as is_contract_with_deal,
  is_guarantee_paid,
  COALESCE(flag_is_HR,FALSE) as is_hr,
  IF(flag_is_invoice_deal = 1, TRUE, FALSE) AS is_invoice_deal,
  dt_closing,
  dt_created_deal,
  dt_due_adjs,
  deal_anchor_due_date as dt_due_deal_anchor,
  dt_due_general_accrual,
  dt_paid_adjs,
  dt_snapshot
FROM 
  base_step4_delay
WHERE 
  payment_status <> 'written down'