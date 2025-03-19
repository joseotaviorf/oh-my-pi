WITH 
get_max_life AS (
    SELECT 
        sk_propose, 
        MAX(mob) AS max_mob_life 
    FROM 
        dw_collection_recovery_quintocred.fact_proposal_signature_payment_timeline
    WHERE 
        ref_month <= DATE_TRUNC('MONTH', CURRENT_DATE)
    GROUP BY 
        sk_propose
),
delinquencies_of_renewal AS (
    SELECT
        id_propose,
        id,
        id_type AS id_type_og,
        original_value AS value,
        is_active,
        id_status,
        amount_paid,
        CASE 
            WHEN (source <> 'MANUAL_LIVING_WITHOUT_PAYMENT' OR source IS NULL) AND is_active THEN id_type
            WHEN (source = 'MANUAL_LIVING_WITHOUT_PAYMENT' AND source IS NOT NULL) AND is_active THEN -1
            WHEN (source = 'MANUAL_LIVING_WITHOUT_PAYMENT' AND source IS NOT NULL) AND NOT(is_active) THEN -7
            WHEN NOT(is_active) AND id_type = 0 THEN -2
            WHEN NOT(is_active) THEN -1 * id_type
            ELSE -99 
        END AS id_type,
        CASE 
            WHEN NOT(is_active) THEN 'CANCELLED'
            WHEN amount_paid >= original_value THEN 'PAID'
            WHEN amount_paid < original_value AND amount_paid > 0 THEN 'IN PAYMENT'
            WHEN amount_paid = 0 OR amount_paid IS NULL THEN 'UNPAID' 
        END AS status,
        'DELINQUENCY' AS gateway, 
        'deliquency' AS category,
        CAST(ts_created AS DATE) AS dt_created,
        DATE_TRUNC('MONTH', ts_created) AS month_ref_creation,
        CAST(dt_due AS DATE) AS dt_due,
        DATE_TRUNC('MONTH', dt_due) AS month_ref_due,
        CAST(dt_paid AS DATE) AS dt_paid,
        DATE_TRUNC('MONTH', dt_paid) AS month_ref_paid
    FROM 
        datalake_rental_guarantee_platform_clean.delinquency
    WHERE 
        id_type IN (0, 4, 5)
),
summary_delinquencies AS (
    SELECT 
        id_propose, 
        month_ref_due,
        COUNT(DISTINCT id) AS n_delinquencies,
        COUNT(DISTINCT CASE WHEN is_active = false THEN id ELSE NULL END) AS n_delinquencies_archived,
        COUNT(DISTINCT CASE WHEN is_active THEN id ELSE NULL END) AS n_delinquencies_active,
        SUM(value) AS amount,
        SUM(CASE WHEN is_active THEN value ELSE NULL END) AS amount_active,
        SUM(CASE WHEN is_active = false THEN value ELSE NULL END) AS amount_archived,
        SUM(amount_paid) AS amount_paid,
        SUM(CASE WHEN is_active THEN amount_paid ELSE NULL END) AS amount_paid_active,
        SUM(CASE WHEN is_active = false THEN amount_paid ELSE NULL END) AS amount_paid_archived,
        ARRAY_AGG(id) AS arr_id_delinquency,
        ARRAY_AGG(CASE WHEN is_active THEN id ELSE NULL END) AS arr_id_delinquency_active,
        ARRAY_AGG(CASE WHEN is_active = false THEN id ELSE NULL END) AS arr_id_delinquency_archived,
        ARRAY_AGG(id_type) AS arr_id_type,
        ARRAY_AGG(CASE WHEN is_active THEN id_type ELSE NULL END) AS arr_id_type_active,
        ARRAY_AGG(CASE WHEN is_active = false THEN id_type ELSE NULL END) AS arr_id_type_archived,
        ARRAY_AGG(dt_created) AS arr_dt_created,
        ARRAY_AGG(CASE WHEN is_active THEN dt_created ELSE NULL END) AS arr_dt_created_active,
        ARRAY_AGG(CASE WHEN is_active = false THEN dt_created ELSE NULL END) AS arr_dt_created_archived,
        ARRAY_AGG(dt_due) AS arr_dt_due,
        ARRAY_AGG(CASE WHEN is_active THEN dt_due ELSE NULL END) AS arr_dt_due_active,
        ARRAY_AGG(CASE WHEN is_active = false THEN dt_due ELSE NULL END) AS arr_dt_due_archived,
        ARRAY_AGG(dt_paid) AS arr_dt_paid,
        ARRAY_AGG(CASE WHEN is_active THEN dt_paid ELSE NULL END) AS arr_dt_paid_active,
        ARRAY_AGG(CASE WHEN is_active = false THEN dt_paid ELSE NULL END) AS arr_dt_paid_archived,
        MIN(month_ref_paid) AS min_month_paid_min,
        MIN(CASE WHEN is_active THEN month_ref_paid ELSE NULL END) AS arr_min_month_paid_min
    FROM 
        delinquencies_of_renewal
    GROUP BY 
        1, 2
),
distance_measure AS (
    SELECT 
        ref_month, 
        m.sk_propose AS sk_propose_append, 
        birth_origin, 
        mob, 
        billing_mode_at_ref, 
        dt_expected_day_renewal, 
        dt_contract_started, 
        dt_ended, 
        n.max_mob_life,
        f.id_propose,
        f.month_ref_due,
        COALESCE(f.n_delinquencies, 0) AS n_delinquencies,
        COALESCE(f.n_delinquencies_archived, 0) AS n_delinquencies_archived,
        COALESCE(f.n_delinquencies_active, 0) AS n_delinquencies_active,
        COALESCE(f.amount, 0) AS amount,
        COALESCE(f.amount_active, 0) AS amount_active,
        COALESCE(f.amount_archived, 0) AS amount_archived,
        COALESCE(f.amount_paid, 0) AS amount_paid,
        COALESCE(f.amount_paid_active, 0) AS amount_paid_active,
        COALESCE(f.amount_paid_archived, 0) AS amount_paid_archived,
        f.arr_id_type,
        f.arr_id_type_active,
        f.arr_id_type_archived,
        f.arr_dt_created,
        f.arr_dt_created_active,
        f.arr_dt_created_archived,
        f.arr_dt_due,
        f.arr_dt_due_active,
        f.arr_dt_due_archived,
        f.arr_dt_paid,
        f.arr_dt_paid_active,
        f.arr_dt_paid_archived,
        f.arr_id_delinquency,
        f.arr_id_delinquency_active,
        f.arr_id_delinquency_archived,
        COALESCE(12 * (YEAR(month_ref_due) - YEAR(ref_month)) + (MONTH(month_ref_due) - MONTH(ref_month)), -1) AS mob_delinquency_distance,
        COALESCE(12 * (YEAR(min_month_paid_min) - YEAR(month_ref_due)) + (MONTH(min_month_paid_min) - MONTH(month_ref_due)), -1) AS mob_delinquency_payment_distance,
        COALESCE(12 * (YEAR(arr_min_month_paid_min) - YEAR(month_ref_due)) + (MONTH(arr_min_month_paid_min) - MONTH(month_ref_due)), -1) AS mob_delinquency_payment_distance_active
    FROM 
        dw_collection_recovery_quintocred.fact_proposal_signature_payment_timeline AS m
    LEFT JOIN 
        get_max_life n 
          ON m.sk_propose = n.sk_propose
    LEFT JOIN 
        summary_delinquencies f 
          ON (m.sk_propose = f.id_propose 
          AND f.month_ref_due >= m.ref_month)
    WHERE 
        m.renewal_status = 'RENEWAL AT MONTH'
        AND ref_month <= DATE_TRUNC('month', current_date) + INTERVAL '1' MONTH
        AND ref_month >= DATE('2023-1-1')
),
agg_data AS (
    SELECT 
        ref_month,
        dt_expected_day_renewal,
        billing_mode_at_ref,
        YEAR(ref_month) AS year_of_renewal_timeline,
        sk_propose_append,
        mob,
        dt_contract_started,
        dt_ended AS dt_ended_append,
        max_mob_life,
        SUM(CASE WHEN mob_delinquency_distance <= 0 THEN n_delinquencies ELSE 0 END) AS qtd_delinquencies, 
        SUM(CASE WHEN mob_delinquency_distance <= 0 THEN amount ELSE 0 END) AS total_amount,
        SUM(CASE WHEN mob_delinquency_distance <= 0 AND mob_delinquency_payment_distance <= 1 THEN amount_paid ELSE 0 END) AS amount_paid,
        ARRAY_AGG(DISTINCT CASE WHEN mob_delinquency_distance <= 0 THEN arr_id_type END) AS arr_id_type_valid,
        ARRAY_AGG(DISTINCT CASE WHEN mob_delinquency_distance <= 0 THEN arr_dt_created END) AS arr_dt_created_valid,
        ARRAY_AGG(DISTINCT CASE WHEN mob_delinquency_distance <= 0 THEN arr_id_delinquency END) AS arr_id_delinquency_valid,
        ARRAY_AGG(DISTINCT CASE WHEN mob_delinquency_distance <= 0 THEN arr_dt_paid END) AS arr_dt_paid_valid,
        SUM(CASE WHEN mob_delinquency_distance <= 0 THEN n_delinquencies_active ELSE 0 END) AS qtd_delinquencies_active, 
        SUM(CASE WHEN mob_delinquency_distance <= 0 THEN amount_active ELSE 0 END) AS total_amount_active,
        SUM(CASE WHEN mob_delinquency_distance <= 0 AND mob_delinquency_payment_distance <= 99 THEN amount_paid_active ELSE 0 END) AS amount_paid_active,
        ARRAY_AGG(DISTINCT CASE WHEN mob_delinquency_distance <= 0 THEN arr_id_type_active END) AS arr_id_type_valid_active,
        ARRAY_AGG(DISTINCT CASE WHEN mob_delinquency_distance <= 0 THEN arr_dt_created_active END) AS arr_dt_created_valid_active,
        ARRAY_AGG(DISTINCT CASE WHEN mob_delinquency_distance <= 0 THEN arr_dt_due_active END) AS arr_dt_due_valid_active,
        ARRAY_AGG(DISTINCT CASE WHEN mob_delinquency_distance <= 0 THEN arr_id_delinquency_active END) AS arr_id_delinquency_valid_active,
        SUM(CASE WHEN mob_delinquency_distance <= 0 THEN n_delinquencies_archived ELSE 0 END) AS qtd_delinquencies_archived, 
        SUM(CASE WHEN mob_delinquency_distance <= 0 THEN amount_archived ELSE 0 END) AS total_amount_archived,
        ARRAY_AGG(DISTINCT CASE WHEN mob_delinquency_distance <= 0 THEN arr_id_type_archived END) AS arr_id_type_archived_valid,
        ARRAY_AGG(DISTINCT CASE WHEN mob_delinquency_distance <= 0 THEN arr_dt_created_archived END) AS arr_dt_created_archived_valid,
        ARRAY_AGG(DISTINCT CASE WHEN mob_delinquency_distance <= 0 THEN arr_dt_due_archived END) AS arr_dt_due_archived_valid,
        ARRAY_AGG(DISTINCT CASE WHEN mob_delinquency_distance <= 0 THEN arr_id_delinquency_archived END) AS arr_id_delinquency_archived_valid,
        ARRAY_AGG(DISTINCT arr_dt_due) AS arr_arr_dt_due,
        ARRAY_AGG(DISTINCT arr_dt_paid) AS arr_arr_dt_paid,
        ARRAY_AGG(DISTINCT arr_id_type) AS arr_id_type,
        ARRAY_AGG(DISTINCT arr_dt_created) AS arr_dt_created,
        ARRAY_AGG(DISTINCT arr_id_delinquency) AS arr_id_delinquency,
        ARRAY_AGG(DISTINCT arr_id_delinquency_active) AS arr_id_delinquency_active,
        ARRAY_AGG(DISTINCT arr_id_delinquency_archived) AS arr_id_delinquency_archived,
        SUM(CASE WHEN mob_delinquency_distance <= 12 THEN n_delinquencies ELSE 0 END) AS qtd_delinquencies_total,
        SUM(CASE WHEN mob_delinquency_distance <= 12 THEN n_delinquencies_active ELSE 0 END) AS qtd_delinquencies_active_total, 
        SUM(CASE WHEN mob_delinquency_distance <= 12 THEN n_delinquencies_archived ELSE 0 END) AS qtd_delinquencies_archived_total,
        SUM(CASE WHEN mob_delinquency_distance <= 12 THEN amount_active ELSE 0 END) AS total_amount_active_annual,
        SUM(CASE WHEN mob_delinquency_distance <= 12 AND mob_delinquency_payment_distance <= 99 THEN amount_paid_active ELSE 0 END) AS amount_paid_active_total_annual,
        MIN(mob_delinquency_distance) AS min_mob_delinquency_distance,
        MIN(mob_delinquency_payment_distance) AS min_mob_delinquency_payment_distance,
        ARRAY_AGG(month_ref_due) AS arr_mdd
    FROM 
        distance_measure 
    GROUP BY 
        1, 2, 3, 4, 5, 6, 7, 8, 9
),
renewal_mob_0 AS (
    SELECT 
        *,
        CASE 
            WHEN qtd_delinquencies = 0 OR (amount_paid >= total_amount) THEN 'A. Adimplente'
            ELSE 'B. Inadimplente' 
        END AS status_compliance,
        CASE 
            WHEN qtd_delinquencies = 0 THEN 'A. Puro Adimplente'
            WHEN qtd_delinquencies > 0 AND (amount_paid >= total_amount) THEN 'B. Adimplente após Dívida'
            ELSE 'C. Inadimplente' 
        END AS status_compliance_v2,
        CASE 
            WHEN qtd_delinquencies = 0 OR (qtd_delinquencies_active = 0 AND qtd_delinquencies_archived > 0) THEN 'A1. LEGACY RENEWAL 0/0'
            WHEN qtd_delinquencies_active > 0 AND (amount_paid_active < total_amount_active) THEN 'A3. LEGACY RENEWAL W ACTIVE DEBT - UNPAID'
            WHEN qtd_delinquencies_active > 0 AND (amount_paid_active >= total_amount_active) THEN 'A4. LEGACY RENEWAL W ACTIVE DEBT - PAID'
            ELSE 'A5. -' 
        END AS status_compliance_v3,
        CASE 
            WHEN dt_ended_append IS NOT NULL AND max_mob_life - mob <= 0 THEN '1. CANCELED'
            ELSE '2. LIVED RENEWAL' 
        END AS status_life,
        mob / 12 AS years_old_at_renewal
    FROM 
        agg_data
),
contact AS (
  SELECT 
    p.sk_propose,
    per.name,
    per.phone,
    per.email
  FROM 
    dw_velo.fact_velo_propose p 
  LEFT JOIN 
    dw_velo.bridge_velo_propose_person bp 
      ON bp.sk_propose = p.sk_propose 
  LEFT JOIN 
      dw_velo.dim_velo_propose_person per 
        ON per.sk_person = bp.sk_person 
  WHERE 
    bp.is_primary_person = true 
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY p.sk_propose ORDER BY per.sk_person) = 1
),
payment_cleaned AS (
  SELECT
    p.id_payment AS id_payment_rgp,
    id_propose AS id_propose_payment,
    status_pay.desc_lvl_1 AS status_payment,
    gateway.desc_lvl_1 AS gateway_payment,
    billing.desc_lvl_1 AS billing_type,
    category.desc_lvl_1 AS category,
    dt_created AS dt_created_payment,
    dt_due AS dt_due_payment,
    due_amount AS payment_value
  FROM 
    datalake_velo.payment p
  LEFT JOIN 
    datalake_velo.junk status_pay 
      ON status_pay.id_junk = p.id_status
  LEFT JOIN 
    datalake_velo.junk gateway 
      ON gateway.id_junk = p.id_payment_gateway
  LEFT JOIN 
    datalake_velo.junk billing 
      ON billing.id_junk = p.id_billing_type
  LEFT JOIN 
    datalake_velo.junk category 
      ON category.id_junk = p.id_payment_category
),
link_report_view AS (
  SELECT
    id AS id_link_checkout,
    id_propose AS id_propose_checkout,
    link AS link,
    flow_type AS flow_type,
    bc.user_insert AS user_insert,
    bc.installments AS installments,
    bc.version AS VERSION,
    dt_due AS dt_due_checkout,
    cast(ts_created AS date) AS dt_created_checkout,
    cast(ts_updated AS date) AS dt_updated_checkout,
    count(DISTINCT CASE
      WHEN pc.status_payment IN ('SUCCESS', 'REFUNDED', 'REFUND_PROCESSING') THEN id_payment_rgp
    END) AS n_payment_success,
    count(DISTINCT CASE
      WHEN pc.status_payment IN ('SUCCESS', 'REFUNDED', 'REFUND_PROCESSING') THEN pc.dt_due_payment
    END) AS n_dt_due,
    sum(CASE
      WHEN pc.status_payment IN ('SUCCESS', 'REFUNDED', 'REFUND_PROCESSING') THEN pc.payment_value
    END) AS total_value,
    min(CASE
      WHEN pc.status_payment IN ('SUCCESS', 'REFUNDED', 'REFUND_PROCESSING') THEN pc.dt_created_payment
    END) AS dt_created_payment,
    max(CASE
      WHEN pc.status_payment IN ('SUCCESS', 'REFUNDED', 'REFUND_PROCESSING') THEN pc.gateway_payment
    END) AS gateway_payment,
    max(CASE
      WHEN pc.status_payment IN ('SUCCESS', 'REFUNDED', 'REFUND_PROCESSING') THEN pc.billing_type
    END) AS billing_type,
    max(CASE
      WHEN pc.status_payment IN ('SUCCESS', 'REFUNDED', 'REFUND_PROCESSING') THEN pc.category
    END) AS category_payment
  FROM 
    datalake_rental_guarantee_platform_clean.bill_checkout bc
  LEFT JOIN
    datalake_rental_guarantee_platform_clean.bill_payment bp 
      ON bp.id_bill = bc.id
  LEFT JOIN 
    payment_cleaned pc 
      ON pc.id_payment_rgp = bp.id_payment
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),
clean_link_payment_table AS (
  SELECT 
    id_link_checkout, 
    CASE 
      WHEN n_payment_success > 0 THEN 'LINK_PAID' 
      ELSE 'LINK_UNPAID' 
    END AS LINK_STATUS,
    dt_created_payment, 
    gateway_payment, 
    billing_type 
  FROM 
    link_report_view 
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_link_checkout ORDER BY dt_created_checkout DESC) = 1
),
base_renewal AS (
  SELECT DISTINCT 
    p.sk_propose AS sk_propose,
    r.dt_due AS dt_due_renewal,
    YEAR(r.dt_due) AS year_of_renewal,
    r.cycle,
    DATE_TRUNC('month', r.dt_due) AS ref_month_renewal,
    p.dt_ended,
    cp.id AS id_imob,
    CASE 
      WHEN DATEDIFF(current_date, r.dt_due) = 0 THEN 'D-0'
      WHEN DATEDIFF(current_date, r.dt_due) = 5 THEN 'D-5'
      WHEN DATEDIFF(current_date, r.dt_due) = 10 THEN 'D-10'
      WHEN DATEDIFF(current_date, r.dt_due) = 15 THEN 'D-15'
      ELSE '' 
    END AS days_step,
    CASE 
      WHEN r.dt_paid IS NULL THEN NULL 
      ELSE r.dt_paid 
    END AS dt_paid_renewal,
    CASE 
      WHEN r.previous_monthly_amount IS NULL THEN pv.monthly_guarantee 
      ELSE r.previous_monthly_amount 
    END AS previous_amount,
    CASE 
      WHEN r.updated_monthly_amount IS NULL THEN NULL 
      ELSE r.updated_monthly_amount 
    END AS current_amount,
    100 - ((CASE WHEN r.updated_monthly_amount = 0 THEN NULL ELSE r.updated_monthly_amount END) * 100) / (COALESCE(r.previous_monthly_amount, pv.monthly_guarantee)) AS value_percent,
    r.price_index_type,
    CASE 
      WHEN c.current_payment_method = 'MONTHLY_CREDIT_CARD' THEN 'Cartao_de_Credito_Mensal' 
      WHEN c.current_payment_method = 'ANNUAL_CREDIT_CARD' THEN 'Cartao_de_Credito_Anual' 
      WHEN c.current_payment_method = 'ANNUAL_BOLETO' THEN 'Boleto_Anual' 
      WHEN c.current_payment_method = 'MONTHLY_BOLETO' THEN 'Boleto_Mensal' 
      ELSE NULL 
    END AS payment_method, 
    CASE 
      WHEN r.dt_paid IS NOT NULL AND p.is_direct_billing = FALSE THEN 'Renovado' 
      WHEN r.dt_paid IS NOT NULL AND p.is_direct_billing = TRUE THEN 'Renovado_Repasse' 
      WHEN r.step IN ('RENEWAL_REMINDER_D0', 'RENEWAL_REMINDER_D3', 'RENEWAL_REMINDER_D7', 'RENEWAL_REMINDER_D15', 'RENEWAL_REMINDER_D25', 'RENEWAL_REMINDER_D30') AND p.is_direct_billing = FALSE THEN 'Em_renovacao'
      WHEN r.step IN ('RENEWAL_REMINDER_D0', 'RENEWAL_REMINDER_D3', 'RENEWAL_REMINDER_D7', 'RENEWAL_REMINDER_D15', 'RENEWAL_REMINDER_D25', 'RENEWAL_REMINDER_D30') AND p.is_direct_billing = TRUE THEN 'Em_renovacao_Repasse_direto'
      WHEN r.step IN ('RENEWED') AND r.dt_paid IS NULL AND p.is_direct_billing = FALSE THEN 'Renovado (ASAAS)' 
      WHEN r.step IN ('DELINQUENCY') THEN 'Inadimplente' 
      ELSE NULL 
    END AS renewal_step_logic, 
    CASE 
      WHEN p.is_direct_billing = TRUE THEN 'Repasse_direto' 
      ELSE 'QuintoCred_cobra' 
    END AS billing_model_at_renewal,
    r.step AS step_from_product,
    bc_renovation.id AS id_link_renewal,
    bc_renovation.link AS link_checkout,
    bc_renovation.ts_created AS link_checkout_creation,
    bc_renovation.dt_due AS dt_due_link_checkout,
    bc_renovation.flow_type,
    bc_partial_link.id AS id_partial_link,
    bc_partial_link.link AS link_checkout_propose,
    bc_partial_link.ts_created AS link_checkout_creation_propose,
    bc_partial_link.dt_due AS dt_due_link_checkout_propose,
    bc_partial_link.flow_type AS flow_type_propose,
    bc_partial_link.installments AS n_installments_partial_link,
    con.name,
    con.phone,
    con.email
  FROM 
    datalake_rental_guarantee_platform_clean.renewal r 
  LEFT JOIN 
    dw_velo.fact_velo_propose p 
      ON p.sk_propose = r.propose 
  LEFT JOIN 
    datalake_rental_guarantee_platform_clean.contract c 
      ON c.id_propose = p.sk_propose 
  LEFT JOIN 
    dw_velo.dim_velo_propose_values pv 
      ON pv.sk_propose_values = p.sk_propose_values 
  LEFT JOIN 
    datalake_rental_guarantee_platform_clean.propose_person pp 
      ON pp.uuid_person = c.id_main_tenant 
  LEFT JOIN 
    contact con 
      ON p.sk_propose = con.sk_propose 
  LEFT JOIN 
    datalake_rental_guarantee_platform_clean.company cp 
      ON cp.id = c.id_real_estate 
  LEFT JOIN 
    datalake_rental_guarantee_platform_clean.bill_checkout bc_renovation 
      ON bc_renovation.id_propose = r.propose 
      AND bc_renovation.flow_type = 'RENOVATION'
      AND ABS(DATEDIFF(r.dt_due, bc_renovation.dt_due)) < 5
  LEFT JOIN 
    datalake_rental_guarantee_platform_clean.bill_checkout bc_partial_link 
      ON bc_partial_link.id_propose = r.propose 
      AND bc_partial_link.flow_type = 'PARTIAL_RENOVATION' 
      AND bc_partial_link.ts_created >= r.dt_due 
      AND (12 * (YEAR(bc_partial_link.ts_created) - YEAR(r.dt_due)) + (MONTH(bc_partial_link.ts_created) - MONTH(r.dt_due))) < 12
      AND (12 * (YEAR(bc_partial_link.ts_created) - YEAR(r.dt_due)) + (MONTH(bc_partial_link.ts_created) - MONTH(r.dt_due))) >= 0
  WHERE 
    r.id > 0 
    AND p.dt_contract_started IS NOT NULL 
),
renewal AS (
  SELECT 
    m.*, 
    f.link_status AS renewal_link_status, 
    f.dt_created_payment AS dt_paid_link_renewal,
    ff.link_status AS partial_link_status, 
    ff.dt_created_payment AS dt_paid_link_partial
  FROM 
    base_renewal m
  LEFT JOIN 
    clean_link_payment_table f 
      ON m.id_link_renewal = f.id_link_checkout
  LEFT JOIN 
    clean_link_payment_table ff 
      ON m.id_partial_link = ff.id_link_checkout
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY sk_propose, year_of_renewal, cycle ORDER BY id_link_renewal DESC, id_partial_link DESC, dt_due_link_checkout_propose DESC) = 1
)
SELECT 
  COALESCE(m.sk_propose, F.sk_propose_append) AS sk_propose_official,
  sk_propose,  
  sk_propose_append,  
  id_imob,  
  id_link_renewal,  
  id_partial_link,  
  arr_id_type_valid AS id_arr_type_valid,
  arr_id_delinquency_valid AS id_arr_delinquency_valid,  
  arr_id_type_valid_active AS id_arr_type_valid_active,  
  arr_id_delinquency_valid_active AS id_arr_delinquency_valid_active,  
  arr_id_type_archived_valid AS id_arr_type_archived_valid,  
  arr_id_delinquency_archived_valid AS id_arr_delinquency_archived_valid,  
  arr_id_type AS id_arr_type,  
  arr_id_delinquency AS id_arr_delinquency,  
  arr_id_delinquency_active AS id_arr_delinquency_active,  
  arr_id_delinquency_archived AS id_arr_delinquency_archived, 
  cycle,  
  ref_month_renewal,  
  days_step,  
  price_index_type,  
  payment_method,  
  renewal_step_logic,  
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
  mob,  
  status_compliance,  
  status_compliance_v2,  
  status_compliance_v3,  
  status_life,  
  years_old_at_renewal,  
  qtd_delinquencies,  
  qtd_delinquencies_active,  
  qtd_delinquencies_archived,  
  qtd_delinquencies_total,  
  qtd_delinquencies_active_total,  
  qtd_delinquencies_archived_total,
  previous_amount,  
  current_amount,  
  value_percent,    
  total_amount,  
  amount_paid,  
  total_amount_active,  
  amount_paid_active,  
  total_amount_archived,  
  total_amount_active_annual,  
  amount_paid_active_total_annual,  
  min_mob_delinquency_distance,  
  min_mob_delinquency_payment_distance,  
  year_of_renewal,  
  CAST(COALESCE(m.ref_month_renewal, F.ref_month) AS DATE) AS ref_month_renewal_coalesce,
  ref_month,  
  year_of_renewal_timeline,  
  arr_dt_created_valid AS dt_arr_created_valid, 
  arr_dt_paid_valid AS dt_arr_paid_valid,  
  arr_dt_created_valid_active AS dt_arr_created_valid_active,  
  arr_dt_due_valid_active AS dt_arr_due_valid_active,  
  arr_dt_created_archived_valid AS dt_arr_created_archived_valid,  
  arr_dt_due_archived_valid AS dt_arr_due_archived_valid,  
  arr_arr_dt_due AS dt_arr_due,  
  arr_arr_dt_paid AS dt_arr_paid,  
  arr_dt_created AS dt_arr_created,   
  COALESCE(m.dt_due_renewal, F.dt_expected_day_renewal) AS dt_due_renewal_coalesce,
  COALESCE(dt_ended, dt_ended_append) AS dt_ended_official,
  dt_due_renewal,  
  dt_ended,  
  dt_paid_renewal,  
  dt_due_link_checkout,  
  dt_due_link_checkout_propose,  
  dt_paid_link_renewal,  
  dt_paid_link_partial,  
  dt_expected_day_renewal,  
  dt_contract_started,  
  dt_ended_append
FROM 
  renewal m
FULL OUTER JOIN 
  renewal_mob_0 f
    ON f.sk_propose_append = m.sk_propose
    AND f.year_of_renewal_timeline = m.year_of_renewal
WHERE 
  COALESCE(
    DATE_TRUNC('MONTH', m.dt_due_renewal), 
    DATE_TRUNC('MONTH', f.dt_expected_day_renewal)
  ) >= DATE('2023-1-1')
