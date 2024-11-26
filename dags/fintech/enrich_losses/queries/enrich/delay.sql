WITH BASE_VENCIMENTOS_PADRONIZADOS AS(
  WITH base_1 AS(
    SELECT
      accrual_year_month,
      cast(ts_due AS date) AS dt_due,
      count(id_external) AS qtd_faturas
    FROM
      datalake_retsuko.invoice
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
          datalake_retsuko.entry e
        LEFT JOIN
          datalake_retsuko_clean.contract c
            ON c.id = e.id_contract
        LEFT JOIN
          datalake_retsuko.invoice i
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
      datalake_retsuko.invoice i
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
      datalake_retsuko.invoice i
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
    bama.*,
    'bill-item' as deal_detection_method
  FROM
    BASE_ACORDOS_METODOLOGIA_ANTIGA as bama
  UNION ALL
  SELECT
    bamn.*,
    'trato-feito' as deal_detection_method
  FROM
    BASE_ACORDOS_METODOLOGIA_NOVA as bamn
),
closing_union AS(
  SELECT
    id_invoice,
    id_contract,
    accrual_year_month,
    closing_month_status,
    due_amount,
    frequency,
    invoice_type,
    contract_guarantee,
    is_guarantee_paid,
    is_before_started,
    is_before_started_raw,
    is_canceled_in_dead_time,
    is_international,
    is_paid_in_closing_day,
    is_writtendown_in_dead_time,
    is_write_off,
    is_contract_write_off,
    has_repair_offboarding_bill_item,
    paid_amount,
    payment_status,
    user,
    origin_factor,
    dt_closing,
    dt_contract_signature,
    dt_annulment,
    dt_due,
    dt_paid,
    dt_sent,
    dt_write_off,
    dt_snapshot
  FROM
    datalake_losses.closing

  UNION

  SELECT
    id_invoice,
    id_contract,
    accrual_year_month,
    closing_month_status,
    due_amount,
    frequency,
    invoice_type,
    contract_guarantee,
    is_guarantee_paid,
    is_before_started,
    is_before_started_raw,
    is_canceled_in_dead_time,
    is_international,
    is_paid_in_closing_day,
    is_writtendown_in_dead_time,
    NULL AS is_write_off,
    NULL AS is_contract_write_off,
    NULL AS has_repair_offboarding_bill_item,
    paid_amount,
    payment_status,
    user,
    origin_factor,
    dt_closing,
    dt_contract_signature,
    dt_annulment,
    dt_due,
    dt_paid,
    dt_sent,
    NULL AS dt_write_off,
    dt_snapshot
  FROM
    datalake_losses.historical_closing
),
base_step0_delay AS(
  SELECT
    fc.*,
    CASE WHEN payment_status = 'paid' AND dt_paid > dt_closing THEN NULL ELSE dt_paid END AS dt_paid_adjs,
    CASE WHEN fc.frequency = 'monthly' THEN v.dt_due ELSE fc.dt_due END AS dt_due_adjs,
    d.dt_created_deal,
    d.deal_detection_method,
    d.dt_min_due_date_at_deal AS deal_anchor_due_date,
    v.dt_due as dt_due_general_accrual
  FROM
    closing_union fc
  LEFT JOIN
    BASE_ACORDOS_GLOBAL d
      ON d.sk_deal_invoice = fc.id_invoice
  LEFT JOIN
    BASE_VENCIMENTOS_PADRONIZADOS v
      ON v.accrual_year_month = fc.accrual_year_month
  WHERE
    TRUE
  -- There`s an exception of deals on january balance due to the accounting window on the moment of the emission of this closing, there`s an alignment between MIS and controlling regarding this.
    AND (is_paid_in_closing_day is FALSE or dt_closing = '2023-01-31')
    AND (payment_status <> 'canceled' and (is_canceled_in_dead_time is FALSE or is_canceled_in_dead_time IS TRUE))

),
base_step1_delay AS(
  SELECT
    *,
    -- There`s an exception of deals on january balance due to the accounting window on the moment of the emission of this closing, there`s an alignment between MIS and controlling regarding this.
    CASE WHEN (deal_anchor_due_date IS NOT NULL AND ((deal_detection_method='bill-item') AND (dt_closing=date('2023-1-31')))) OR (deal_anchor_due_date IS NOT NULL AND NOT(dt_closing=date('2023-1-31'))) THEN 1 ELSE 0 END AS flag_is_invoice_deal,
    datediff(dt_due_adjs, dt_closing) AS delta_days,
    datediff(deal_anchor_due_date, dt_created_deal) AS delay_at_deal_creation,
    datediff(deal_anchor_due_date, dt_closing) AS full_delay_at_deal
  FROM
    base_step0_delay
),
base_aux_ref_contract_deals AS(
  SELECT
    DISTINCT id_contract,
    user,
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
    user,
    dt_closing,
    id_invoice,
    row_number() OVER(PARTITION BY id_contract, user, dt_closing ORDER BY deal_anchor_due_date ASC, dt_created_deal ASC) AS deal_order
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
      ON (deal_age.id_contract = m.id_contract) AND (deal_age.dt_closing = m.dt_closing) AND (deal_age.user = m.user) AND (m.id_invoice = deal_age.id_invoice)
),

base_step2_delay_append AS (

  SELECT
    DISTINCT id_contract,
    user,
    dt_closing,
    min(delay_at_deal_creation) as bigger_anchor_deal_at_contract
  FROM
     base_step2_delay
  WHERE
     flas_contract_has_deal = 1
  GROUP BY
     1,2,3
),


base_step2_delay_mid AS(
  SELECT
    m.*,
    f.bigger_anchor_deal_at_contract,
  -- RULE A: Current on 2022
  -- Set de delay on the time of the anchor of the deal, doesn`t look if the payment is up to date
    CASE WHEN flag_is_invoice_deal = 1 THEN least(full_delay_at_deal, delta_days) ELSE delta_days END AS deal_delay_rule_a,
  -- RULE B: Verifies if the de delay of the deal invoice is greater than the delay of the deal date, if not it keeps the delay of the deal date
    CASE WHEN flag_is_invoice_deal = 1 AND deal_order=1 THEN least(delta_days, delay_at_deal_creation) ELSE delta_days END AS deal_delay_rule_b,
  -- RULE C: Verifies if the contract has parcels on delay, if not, the delay is set to the moment of the deal, if yes it will use the delay of the anchor.
    CASE WHEN flag_is_invoice_deal = 1 AND flag_deal_status_on_delay = 'DEAL IN DELAY' THEN full_delay_at_deal
         WHEN flag_is_invoice_deal = 1 AND flag_deal_status_on_delay = 'DEAL ON TIME. DELAY AT ANCHOR' THEN delay_at_deal_creation
         WHEN flag_is_invoice_deal = 0 THEN delta_days END AS deal_delay_rule_c,
  -- RULE D: Verifies if the contract has parcels on delay, if not, it will use the delay of the delay of the deal date plus anchor.
    CASE WHEN flag_is_invoice_deal = 1 AND flag_deal_status_on_delay = 'DEAL IN DELAY' THEN delta_days + delay_at_deal_creation
         WHEN flag_is_invoice_deal = 1 AND flag_deal_status_on_delay = 'DEAL ON TIME. DELAY AT ANCHOR' THEN delay_at_deal_creation
         WHEN flag_is_invoice_deal = 0 THEN delta_days END AS deal_delay_rule_d,

  -- RULE E: In the event of a broken deal ALL delayed debt will be further contaminated
    CASE WHEN flag_is_invoice_deal = 1 AND flag_deal_status_on_delay = 'DEAL IN DELAY' THEN delta_days + coalesce(f.bigger_anchor_deal_at_contract,0)
         WHEN flag_is_invoice_deal = 1 AND flag_deal_status_on_delay = 'DEAL ON TIME. DELAY AT ANCHOR' THEN delay_at_deal_creation
         WHEN flag_is_invoice_deal = 0 AND flas_contract_has_deal = 1 AND delta_days < 0 THEN delta_days + coalesce(f.bigger_anchor_deal_at_contract,0)
         WHEN flag_is_invoice_deal = 0 AND  flas_contract_has_deal = 1 AND delta_days >=0 THEN delta_days
         WHEN flag_is_invoice_deal = 0 AND  flas_contract_has_deal = 0 THEN delta_days
        END AS deal_delay_rule_e
  FROM
    base_step2_delay m
  LEFT JOIN
     base_step2_delay_append as f
     ON f.id_contract = m.id_contract and f.dt_closing = m.dt_closing and m.user = f.user
),


base_aux_ref_contract_delays AS(
  SELECT
    dt_closing,
    id_contract,
    user,
    min(deal_delay_rule_a) AS delay_contaminated_range_rule_a,
    min(deal_delay_rule_b) AS delay_contaminated_range_rule_b,
    min(deal_delay_rule_c) AS delay_contaminated_range_rule_c,
    min(deal_delay_rule_d) AS delay_contaminated_range_rule_d,
    min(deal_delay_rule_e) AS delay_contaminated_range_rule_e
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
    OR frequency = 'early-termination'
    OR frequency = 'pos rental'
    OR frequency = 'pos-rental'
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
    aux.delay_contaminated_range_rule_b,
    aux.delay_contaminated_range_rule_a,
    aux.delay_contaminated_range_rule_c,
    aux.delay_contaminated_range_rule_d,
    aux.delay_contaminated_range_rule_e,
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
    CASE WHEN delay_contaminated_range_rule_a <= -181 THEN 'TotalM +6 (>181 days)'
         WHEN delay_contaminated_range_rule_a <= -151 THEN 'TotalM +5 (151-180 days)'
         WHEN delay_contaminated_range_rule_a <= -121 THEN 'TotalM +4 (121-150 days)'
         WHEN delay_contaminated_range_rule_a <= -91 THEN 'TotalM +3 (91-120 days)'
         WHEN delay_contaminated_range_rule_a <= -61 THEN 'TotalM +2 (61-90 days)'
         WHEN delay_contaminated_range_rule_a <= -31 THEN 'TotalM +1 (31-60 days)'
         WHEN delay_contaminated_range_rule_a <= -1 THEN 'TotalM +0 (1-30 days)'
         ELSE 'TotalCurrent'
    END AS pd_range_rule_a,
    CASE WHEN delay_contaminated_range_rule_b <= -181 THEN 'TotalM +6 (>181 days)'
         WHEN delay_contaminated_range_rule_b <= -151 THEN 'TotalM +5 (151-180 days)'
         WHEN delay_contaminated_range_rule_b <= -121 THEN 'TotalM +4 (121-150 days)'
         WHEN delay_contaminated_range_rule_b <= -91 THEN 'TotalM +3 (91-120 days)'
         WHEN delay_contaminated_range_rule_b <= -61 THEN 'TotalM +2 (61-90 days)'
         WHEN delay_contaminated_range_rule_b <= -31 THEN 'TotalM +1 (31-60 days)'
         WHEN delay_contaminated_range_rule_b <= -1 THEN 'TotalM +0 (1-30 days)'
         ELSE 'TotalCurrent'
    END AS pd_range_rule_b,
    CASE WHEN delay_contaminated_range_rule_c <= -181 THEN 'TotalM +6 (>181 days)'
         WHEN delay_contaminated_range_rule_c <= -151 THEN 'TotalM +5 (151-180 days)'
         WHEN delay_contaminated_range_rule_c <= -121 THEN 'TotalM +4 (121-150 days)'
         WHEN delay_contaminated_range_rule_c <= -91 THEN 'TotalM +3 (91-120 days)'
         WHEN delay_contaminated_range_rule_c <= -61 THEN 'TotalM +2 (61-90 days)'
         WHEN delay_contaminated_range_rule_c <= -31 THEN 'TotalM +1 (31-60 days)'
         WHEN delay_contaminated_range_rule_c <= -1 THEN 'TotalM +0 (1-30 days)'
         ELSE 'TotalCurrent'
    END AS pd_range_rule_c,
    CASE WHEN delay_contaminated_range_rule_d <= -181 THEN 'TotalM +6 (>181 days)'
         WHEN delay_contaminated_range_rule_d <= -151 THEN 'TotalM +5 (151-180 days)'
         WHEN delay_contaminated_range_rule_d <= -121 THEN 'TotalM +4 (121-150 days)'
         WHEN delay_contaminated_range_rule_d <= -91 THEN 'TotalM +3 (91-120 days)'
         WHEN delay_contaminated_range_rule_d <= -61 THEN 'TotalM +2 (61-90 days)'
         WHEN delay_contaminated_range_rule_d <= -31 THEN 'TotalM +1 (31-60 days)'
         WHEN delay_contaminated_range_rule_d <= -1 THEN 'TotalM +0 (1-30 days)'
         ELSE 'TotalCurrent'
    END AS pd_range_rule_d,
    CASE WHEN delay_contaminated_range_rule_E <= -181 THEN 'TotalM +6 (>181 days)'
         WHEN delay_contaminated_range_rule_E <= -151 THEN 'TotalM +5 (151-180 days)'
         WHEN delay_contaminated_range_rule_E <= -121 THEN 'TotalM +4 (121-150 days)'
         WHEN delay_contaminated_range_rule_E <= -91 THEN 'TotalM +3 (91-120 days)'
         WHEN delay_contaminated_range_rule_E <= -61 THEN 'TotalM +2 (61-90 days)'
         WHEN delay_contaminated_range_rule_E <= -31 THEN 'TotalM +1 (31-60 days)'
         WHEN delay_contaminated_range_rule_E <= -1 THEN 'TotalM +0 (1-30 days)'
         ELSE 'TotalCurrent'
    END AS pd_range_rule_e,
    CASE WHEN flag_is_HR IS TRUE THEN 'HR'
         ELSE 'LR'
    END AS flag_risk
  FROM
    base_step3_delay
),
base_step5_delay AS(
SELECT
  id_invoice,
  id_contract,
  accrual_year_month,
  deal_delay_rule_a,
  deal_delay_rule_b,
  deal_delay_rule_c,
  deal_delay_rule_d,
  deal_delay_rule_e,
  deal_order,
  flag_deal_status_on_delay as deal_status,
  bigger_anchor_deal_at_contract,
  delay_at_deal_creation,
  delay_contaminated_range_rule_a,
  delay_contaminated_range_rule_b,
  delay_contaminated_range_rule_c,
  delay_contaminated_range_rule_d,
  delay_contaminated_range_rule_e,
  CASE
      WHEN deal_delay_rule_a >= 0 THEN 'a. Current'
      WHEN deal_delay_rule_a >= -30 THEN 'b. 1-30'
      WHEN deal_delay_rule_a >= -60 THEN 'c. 31-60'
      WHEN deal_delay_rule_a >= -90 THEN 'd. 61-90'
      WHEN deal_delay_rule_a >= -120 THEN 'e. 91-120'
      WHEN deal_delay_rule_a >= -150 THEN 'f. 121-150'
      WHEN deal_delay_rule_a >= -180 THEN 'g. 151-180'
      ELSE 'h. acima de 180'
  END AS delay_invoice_range_a,
  CASE
      WHEN deal_delay_rule_b >= 0 THEN 'a. Current'
      WHEN deal_delay_rule_b >= -30 THEN 'b. 1-30'
      WHEN deal_delay_rule_b >= -60 THEN 'c. 31-60'
      WHEN deal_delay_rule_b >= -90 THEN 'd. 61-90'
      WHEN deal_delay_rule_b >= -120 THEN 'e. 91-120'
      WHEN deal_delay_rule_b >= -150 THEN 'f. 121-150'
      WHEN deal_delay_rule_b >= -180 THEN 'g. 151-180'
      ELSE 'h. acima de 180'
  END AS delay_invoice_range_b,
  CASE
      WHEN deal_delay_rule_d >= 0 THEN 'a. Current'
      WHEN deal_delay_rule_d >= -30 THEN 'b. 1-30'
      WHEN deal_delay_rule_d >= -60 THEN 'c. 31-60'
      WHEN deal_delay_rule_d >= -90 THEN 'd. 61-90'
      WHEN deal_delay_rule_d >= -120 THEN 'e. 91-120'
      WHEN deal_delay_rule_d >= -150 THEN 'f. 121-150'
      WHEN deal_delay_rule_d >= -180 THEN 'g. 151-180'
      ELSE 'h. acima de 180'
  END AS delay_invoice_range_d,
  CASE
      WHEN deal_delay_rule_e >= 0 THEN 'a. Current'
      WHEN deal_delay_rule_e >= -30 THEN 'b. 1-30'
      WHEN deal_delay_rule_e >= -60 THEN 'c. 31-60'
      WHEN deal_delay_rule_e >= -90 THEN 'd. 61-90'
      WHEN deal_delay_rule_e >= -120 THEN 'e. 91-120'
      WHEN deal_delay_rule_e >= -150 THEN 'f. 121-150'
      WHEN deal_delay_rule_e >= -180 THEN 'g. 151-180'
      ELSE 'h. acima de 180'
  END AS delay_invoice_range_e,
  CASE
      WHEN pd_range_rule_a = 'TotalCurrent' THEN 'a. Current'
      WHEN pd_range_rule_a = 'TotalM +0 (1-30 days)' THEN 'b. 1-30'
      WHEN pd_range_rule_a = 'TotalM +1 (31-60 days)' THEN 'c. 31-60'
      WHEN pd_range_rule_a = 'TotalM +2 (61-90 days)' THEN 'd. 61-90'
      WHEN pd_range_rule_a = 'TotalM +3 (91-120 days)' THEN 'e. 91-120'
      WHEN pd_range_rule_a = 'TotalM +4 (121-150 days)' THEN 'f. 121-150'
      WHEN pd_range_rule_a = 'TotalM +5 (151-180 days)' THEN 'g. 151-180'
      WHEN pd_range_rule_a = 'TotalM +6 (>181 days)' THEN 'h. acima de 180'
  END AS delay_contamined_range_a,
  CASE
      WHEN pd_range_rule_b = 'TotalCurrent' THEN 'a. Current'
      WHEN pd_range_rule_b = 'TotalM +0 (1-30 days)' THEN 'b. 1-30'
      WHEN pd_range_rule_b = 'TotalM +1 (31-60 days)' THEN 'c. 31-60'
      WHEN pd_range_rule_b = 'TotalM +2 (61-90 days)' THEN 'd. 61-90'
      WHEN pd_range_rule_b = 'TotalM +3 (91-120 days)' THEN 'e. 91-120'
      WHEN pd_range_rule_b = 'TotalM +4 (121-150 days)' THEN 'f. 121-150'
      WHEN pd_range_rule_b = 'TotalM +5 (151-180 days)' THEN 'g. 151-180'
      WHEN pd_range_rule_b = 'TotalM +6 (>181 days)' THEN 'h. acima de 180'
  END AS delay_contamined_range_b,
  CASE
      WHEN pd_range_rule_d = 'TotalCurrent' THEN 'a. Current'
      WHEN pd_range_rule_d = 'TotalM +0 (1-30 days)' THEN 'b. 1-30'
      WHEN pd_range_rule_d = 'TotalM +1 (31-60 days)' THEN 'c. 31-60'
      WHEN pd_range_rule_d = 'TotalM +2 (61-90 days)' THEN 'd. 61-90'
      WHEN pd_range_rule_d = 'TotalM +3 (91-120 days)' THEN 'e. 91-120'
      WHEN pd_range_rule_d = 'TotalM +4 (121-150 days)' THEN 'f. 121-150'
      WHEN pd_range_rule_d = 'TotalM +5 (151-180 days)' THEN 'g. 151-180'
      WHEN pd_range_rule_d = 'TotalM +6 (>181 days)' THEN 'h. acima de 180'
  END AS delay_contamined_range_d,
  CASE
      WHEN pd_range_rule_e = 'TotalCurrent' THEN 'a. Current'
      WHEN pd_range_rule_e = 'TotalM +0 (1-30 days)' THEN 'b. 1-30'
      WHEN pd_range_rule_e = 'TotalM +1 (31-60 days)' THEN 'c. 31-60'
      WHEN pd_range_rule_e = 'TotalM +2 (61-90 days)' THEN 'd. 61-90'
      WHEN pd_range_rule_e = 'TotalM +3 (91-120 days)' THEN 'e. 91-120'
      WHEN pd_range_rule_e = 'TotalM +4 (121-150 days)' THEN 'f. 121-150'
      WHEN pd_range_rule_e = 'TotalM +5 (151-180 days)' THEN 'g. 151-180'
      WHEN pd_range_rule_e = 'TotalM +6 (>181 days)' THEN 'h. acima de 180'
  END AS delay_contamined_range_e,
  delta_days,
  due_amount,
  frequency,
  full_delay_at_deal,
  IF(is_guarantee_paid is TRUE, 'PAID','FREE') as guarantee_type,
  DATE_FORMAT(deal_anchor_due_date, 'MMyyyy') as invoice_competence_renegotiated,
  payment_status,
  pd_range_rule_a,
  pd_range_rule_b,
  pd_range_rule_c,
  pd_range_rule_d,
  pd_range_rule_e,
  flag_risk as risk_type,
  user,
  is_before_started,
  flas_contract_has_deal as is_contract_with_deal,
  COALESCE(flag_is_HR,FALSE) as is_hr,
  IF(flag_is_invoice_deal = 1, TRUE, FALSE) AS is_invoice_deal,
  is_international,
  is_writtendown_in_dead_time,
  has_repair_offboarding_bill_item,
  is_write_off,
  is_contract_write_off,
  dt_closing,
  dt_created_deal,
  dt_due_adjs,
  deal_anchor_due_date as dt_due_deal_anchor,
  dt_due_general_accrual,
  dt_paid_adjs,
  dt_snapshot,
  dt_write_off
FROM
  base_step4_delay
)
SELECT
  id_invoice,
  id_contract,
  accrual_year_month,
  deal_delay_rule_a,
  deal_delay_rule_b,
  deal_delay_rule_c,
  deal_delay_rule_d,
  deal_delay_rule_e,
  deal_order,
  deal_status,
  bigger_anchor_deal_at_contract,
  delay_at_deal_creation,
  delay_contaminated_range_rule_a,
  delay_contaminated_range_rule_b,
  delay_contaminated_range_rule_c,
  delay_contaminated_range_rule_d,
  delay_contaminated_range_rule_e,
  delay_invoice_range_a,
  delay_invoice_range_b,
  delay_invoice_range_d,
  delay_invoice_range_e,
  CASE
      WHEN DATE_TRUNC('month', dt_snapshot) - INTERVAL '1' MONTH <= DATE('2022-12-01') THEN delay_invoice_range_b
      WHEN DATE_TRUNC('month', dt_snapshot) - INTERVAL '1' MONTH = DATE('2023-01-01') THEN delay_invoice_range_a
      WHEN DATE_TRUNC('month', dt_snapshot) - INTERVAL '1' MONTH BETWEEN DATE('2023-02-01') AND DATE('2023-05-01') THEN delay_invoice_range_b
      WHEN DATE_TRUNC('month', dt_snapshot) - INTERVAL '1' MONTH >= DATE('2023-06-01') THEN delay_invoice_range_e
  END AS delay_invoice_range,
  delay_contamined_range_a,
  delay_contamined_range_b,
  delay_contamined_range_d,
  delay_contamined_range_e,
  CASE
      WHEN DATE_TRUNC('month', dt_snapshot) - INTERVAL '1' MONTH <= DATE('2022-12-01') THEN delay_contamined_range_b
      WHEN DATE_TRUNC('month', dt_snapshot) - INTERVAL '1' MONTH = DATE('2023-01-01') THEN delay_contamined_range_a
      WHEN DATE_TRUNC('month', dt_snapshot) - INTERVAL '1' MONTH BETWEEN DATE('2023-02-01') AND DATE('2023-05-01') THEN delay_contamined_range_b
      WHEN DATE_TRUNC('month', dt_snapshot) - INTERVAL '1' MONTH >= DATE('2023-06-01') THEN delay_contamined_range_e
  END AS delay_contamined_range,
  delta_days,
  due_amount,
  frequency,
  full_delay_at_deal,
  guarantee_type,
  invoice_competence_renegotiated,
  payment_status,
  pd_range_rule_a,
  pd_range_rule_b,
  pd_range_rule_c,
  pd_range_rule_d,
  pd_range_rule_e,
  risk_type,
  user,
  is_before_started,
  is_contract_with_deal,
  is_hr,
  is_invoice_deal,
  is_international,
  is_writtendown_in_dead_time,
  has_repair_offboarding_bill_item,
  is_write_off,
  is_contract_write_off,
  dt_closing,
  dt_created_deal,
  dt_due_adjs,
  dt_due_deal_anchor,
  dt_due_general_accrual,
  dt_paid_adjs,
  dt_write_off,
  dt_snapshot
FROM
  base_step5_delay
