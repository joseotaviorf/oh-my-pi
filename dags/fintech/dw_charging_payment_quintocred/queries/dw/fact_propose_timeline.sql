WITH
base_omie AS (
  SELECT 
    fvte.*,
    CASE 
      WHEN sk_category = '1.01.01' 
        THEN 'monthly'
      ELSE 'annual'
    END AS subscription_type
  FROM 
    dw_velo.fact_velo_transaction_entries AS fvte
  LEFT JOIN 
    dw_velo.dim_velo_omie_client dvoc 
    ON fvte.sk_omie_client = dvoc.sk_client
  WHERE 
    sk_category IN ( '1.01.02', '1.01.01' )
    AND extract( YEAR FROM dt_due ) = 2024
    AND is_occurency = FALSE
  QUALIFY
    ROW_NUMBER() OVER ( 
      PARTITION BY sk_propose 
      ORDER BY dt_due DESC 
    ) = 1
),
mensalidade_omie AS (
  SELECT DISTINCT
    sk_propose,
    CASE
      WHEN subscription_type = 'annual' 
        THEN due_amount / 12
      ELSE due_amount
    END AS monthly_value,
    CASE
      WHEN subscription_type = 'monthly' 
        THEN due_amount * 12
      ELSE due_amount
    END AS annual_value
  FROM 
    base_omie
),
dim_date AS (
  SELECT DISTINCT
    month_start
  FROM 
    dw_public.dim_date
  WHERE 
    date <= current_date()
),
all_renewal AS (
  SELECT DISTINCT 
    id,
    propose AS sk_propose, 
    previous_monthly_amount, 
    updated_monthly_amount, 
    dt_due AS dt_renewal,
    step,
    price_index_type,
    DATE( date_trunc( 'MONTH', dt_due )) AS previous_month_renewal, 
    LEAD( DATE( date_trunc('MONTH', dt_due ))) OVER( PARTITION BY r.propose ORDER BY ts_created ASC ) AS next_month_renewal,
    ts_created,
    ROW_NUMBER() OVER( 
      PARTITION BY propose 
      ORDER BY ts_created DESC 
    ) AS rn  
  FROM 
    datalake_rental_guarantee_platform_clean.renewal r
),
renewal AS (
  SELECT 
    id,
    sk_propose, 
    previous_monthly_amount, 
    updated_monthly_amount, 
    dt_renewal,
    step,
    price_index_type,
    previous_month_renewal, 
    add_months(next_month_renewal,-1) month_end_renewal,
    ts_created,
    rn  
  from all_renewal
),
first_last_line_renewal AS (
SELECT 
  sk_propose,
  MIN( ts_created ) AS min_ts_created
FROM 
  renewal
GROUP BY 1
),
first_renewal_value as (
  SELECT DISTINCT 
    r.sk_propose,
    r.previous_monthly_amount AS first_monthly_value_mod,
    r.previous_monthly_amount * 12 AS first_annual_value_mod
  FROM
    renewal r
  INNER JOIN
    first_last_line_renewal fr
    ON  r.sk_propose = fr.sk_propose
    AND r.ts_created = fr.min_ts_created
),
propose_aud AS (
  SELECT 
    aud.id AS id_propose,
    p.dt_contract_started,
    monthly_value AS monthly_value_mod,
    aud.annual_value AS annual_value_mod,
    rev.ts_created AS ts_started_mod,
    DATE( rev.ts_created ) dt_started_mod,
    LEAD( DATE( rev.ts_created )) OVER( 
      PARTITION BY aud.id 
      ORDER BY rev.ts_created ASC 
    ) AS dt_ended_mod,
    ROW_NUMBER() OVER(
      PARTITION BY aud.id 
      ORDER BY DATE( rev.ts_created ) ASC 
    ) AS ordem_mod
  FROM
    datalake_rental_guarantee_platform_clean.propose_aud aud
  LEFT JOIN
    datalake_rental_guarantee_platform_clean.rev_info rev
    ON aud.rev = rev.rev
  LEFT JOIN dw_velo.fact_velo_propose p
    ON aud.id = p.sk_propose
  WHERE
    aud.monthly_value_mod = true
),
propose_mod AS (
  SELECT
    p.id_propose,
    dt_contract_started,
    monthly_value_mod,
    annual_value_mod,
    ts_started_mod,
    dt_started_mod,
    dt_ended_mod AS dt_ended_mod_original,
    date_trunc( 'MONTH', dt_started_mod ) AS month_start_mod,
    date_trunc( 'MONTH', add_months( dt_ended_mod,-1 )) AS month_ended_mod,
    ordem_mod
  FROM 
    propose_aud p
),
first_line_propose_aud AS (
  SELECT 
    id_propose,
    MIN( ts_started_mod ) AS ts_first_start_mod
  FROM
    propose_mod
  GROUP BY 1
),
first_propose_value AS (
  SELECT DISTINCT
    pm.id_propose,
    pm.monthly_value_mod AS first_monthly_value_mod,
    pm.annual_value_mod AS first_annual_value_mod
  FROM 
    propose_mod pm
  INNER JOIN
    first_line_propose_aud f
    ON  pm.id_propose = f.id_propose
    AND pm.ts_started_mod = f.ts_first_start_mod
),
base_propose AS (
  SELECT
    p.sk_propose,
    p.is_direct_billing,
    p.dt_contract_started,
    p.dt_ended_official AS dt_ended,
    IF(
      DAY( dt_contract_started )
      >
      DAY(LAST_DAY( p.dt_ended_official ) ),
      DATE( dateadd( DAY, 5, DATE( LAST_DAY( p.dt_ended_official ) ) ) ),
      DATE( dateadd( DAY, 5, DATE( CONCAT( 
        CAST( YEAR( p.dt_ended_official) AS VARCHAR(10) ), 
        '-', 
        CAST( MONTH( p.dt_ended_official) AS VARCHAR(10) ), 
        '-', 
        DAY( dt_contract_started ) 
      ) ) ) ) ) AS dt_cancellation_limit,
    IF(
      pv.monthly_guarantee = 0,
      omie.monthly_value,
      pv.monthly_guarantee
    ) AS monthly_guarantee,
    IF(
      pv.monthly_guarantee = 0,
      omie.monthly_value * 12,
      pv.annual_guarantee
    ) AS annual_guarantee,
    pv.monthly_guarantee AS monthly_value_propose,
    pv.annual_guarantee AS annual_value_propose,
    pv.total_package_amount
  FROM 
    dw_velo.fact_velo_propose p
  LEFT JOIN 
    dw_velo.dim_velo_junk djk 
    ON p.sk_propose_status = djk.sk_junk
  LEFT JOIN 
    dw_velo.dim_velo_propose_values pv
    ON p.sk_propose_values = pv.sk_propose_values
  LEFT JOIN 
    mensalidade_omie omie
    ON omie.sk_propose = p.sk_propose
  WHERE 
    p.is_contract
    AND djk.desc_lvl_1 <> 'Contrato Assinado mas não pago'
    AND djk.desc_lvl_1 <> 'Proposta Cancelada'
),
base_propose_timeline AS (
  SELECT DISTINCT
    dd.month_start,
    b.sk_propose,
    b.is_direct_billing,
    b.dt_contract_started,
    b.dt_ended,
    dt_cancellation_limit,
    months_between( 
      COALESCE( date_trunc( 'MONTH', b.dt_ended ),date_trunc( 'MONTH', current_date() )),date_trunc( 'MONTH', b.dt_contract_started )
    ) AS months_life_contract,
    f.first_monthly_value_mod,
    f.first_annual_value_mod,
    CASE
      WHEN DATE_DIFF( b.dt_ended, b.dt_contract_started ) < 11 
        THEN FALSE
      WHEN dd.month_start = date_trunc( 'MONTH', dt_ended ) 
        AND dt_ended <= dt_cancellation_limit 
        THEN FALSE
      ELSE TRUE
    END AS month_chargeble,
    COALESCE(
      CASE
        WHEN DATE_DIFF(b.dt_ended, b.dt_contract_started) < 11 
          THEN 0
        WHEN dd.month_start = date_trunc('MONTH',dt_ended) 
        AND dt_ended <= dt_cancellation_limit 
          THEN 0 
        WHEN date_trunc('MONTH', current_date) = date_trunc('MONTH',r.dt_renewal) 
        AND current_date <= r.dt_renewal 
        AND r.step NOT IN('RENEWED', 'DELINQUENCY') 
          THEN r.previous_monthly_amount 
        WHEN r.dt_renewal > DATE('2024-02-15') 
        AND price_index_type NOT IN ('AGREEMENT') 
        AND r.previous_monthly_amount > r.updated_monthly_amount 
          THEN r.previous_monthly_amount
        WHEN r.step NOT IN('RENEWED','DELINQUENCY') 
          THEN coalesce( coalesce( r.previous_monthly_amount, f.first_monthly_value_mod), b.monthly_guarantee)
        ELSE coalesce(coalesce(r.updated_monthly_amount, f.first_monthly_value_mod), b.monthly_guarantee) 
      END,
      0 ) AS monthly_guarantee_renewal,
    COALESCE(
      CASE
        WHEN DATE_DIFF( b.dt_ended, b.dt_contract_started ) < 11 
          THEN 0
        WHEN dd.month_start = date_trunc( 'MONTH', dt_ended ) 
        AND dt_ended<=dt_cancellation_limit 
          THEN 0
        ELSE COALESCE( COALESCE( pm.monthly_value_mod, f.first_monthly_value_mod ), monthly_value_propose )
      END,
    0) AS monthly_guarantee_propose_aud,
    monthly_value_propose,
    b.annual_guarantee AS annual_value_propose,
    b.total_package_amount,
    CASE 
      WHEN dd.month_start < date_trunc( 'MONTH', b.dt_ended ) 
      OR b.dt_ended IS NULL 
        THEN 'ATIVO' 
      ELSE 'FINALIZADO' 
    END AS status_at_ref,
    CASE 
      WHEN dd.month_start <= date_trunc( 'MONTH', b.dt_ended ) 
      OR b.dt_ended IS NULL 
        THEN months_between( dd.month_start, b.dt_contract_started ) 
      ELSE NULL 
    END AS mob_of_life,
    CASE 
      WHEN dd.month_start >= date_trunc('MONTH', b.dt_ended) 
      AND b.dt_ended IS NOT NULL 
        THEN months_between( dd.month_start, b.dt_ended ) 
      ELSE NULL 
    END AS mob_of_death
  FROM 
    base_propose b
  LEFT JOIN 
    first_renewal_value f
    ON b.sk_propose = f.sk_propose
  LEFT JOIN 
    dim_date dd
    ON dd.month_start 
    BETWEEN 
      date_trunc( 'MONTH', dt_contract_started ) 
      AND date_trunc( 'MONTH', COALESCE( dt_ended, current_date ) )
  LEFT JOIN 
    renewal r
    ON b.sk_propose = r.sk_propose 
    AND b.sk_propose = f.sk_propose
    AND dd.month_start 
    BETWEEN 
      r.previous_month_renewal 
      AND COALESCE( COALESCE( r.month_end_renewal, b.dt_ended ), current_date )
  LEFT JOIN 
    propose_mod pm
    ON b.sk_propose = pm.id_propose
    AND dd.month_start 
    BETWEEN 
      pm.month_start_mod 
      AND COALESCE( COALESCE( pm.month_ended_mod, b.dt_ended ), current_date )
)
SELECT 
  sk_propose,
  month_start,
  months_life_contract,
  month_chargeble,
  monthly_guarantee_renewal,
  monthly_guarantee_propose_aud,
  monthly_value_propose,
  first_monthly_value_mod,
  first_annual_value_mod,
  annual_value_propose,
  total_package_amount,
  status_at_ref,
  mob_of_life,
  mob_of_death,
  monthly_guarantee_renewal * 12 AS annual_guarantee_renewal,
  monthly_guarantee_propose_aud * 12 AS annual_guarantee_propose_aud,
  is_direct_billing,
  dt_contract_started,
  dt_ended,
  dt_cancellation_limit
FROM
  base_propose_timeline
WHERE
  sk_propose NOT IN ( 23244, 23245 )
