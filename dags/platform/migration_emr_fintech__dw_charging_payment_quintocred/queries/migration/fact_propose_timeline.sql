WITH base_omie AS (
  SELECT
    *,
    subscription_type
  FROM (
    SELECT
      fvte.*,
      CASE WHEN sk_category = '1.01.01' THEN 'monthly' ELSE 'annual' END AS subscription_type,
      ROW_NUMBER() OVER (PARTITION BY sk_propose ORDER BY dt_due DESC) AS _w
    FROM dw_velo.fact_velo_transaction_entries AS fvte
    LEFT JOIN dw_velo.dim_velo_omie_client AS dvoc
      ON fvte.sk_omie_client = dvoc.sk_client
    WHERE
      sk_category IN ('1.01.02', '1.01.01')
      AND EXTRACT(YEAR FROM dt_due) = 2024
      AND is_occurency = FALSE
  ) AS _t
  WHERE
    _w = 1
), mensalidade_omie AS (
  SELECT DISTINCT
    sk_propose,
    CASE WHEN subscription_type = 'annual' THEN due_amount / 12 ELSE due_amount END AS monthly_value,
    CASE WHEN subscription_type = 'monthly' THEN due_amount * 12 ELSE due_amount END AS annual_value
  FROM base_omie
), dim_date AS (
  SELECT DISTINCT
    month_start
  FROM dw_public.dim_date
  WHERE
    date <= CURRENT_DATE
), all_renewal AS (
  SELECT DISTINCT
    id,
    propose AS sk_propose,
    COALESCE(s.previous_monthly_amount, r.previous_monthly_amount) AS previous_monthly_amount,
    COALESCE(s.updated_monthly_amount, r.updated_monthly_amount) AS updated_monthly_amount,
    r.dt_due AS dt_renewal,
    step,
    COALESCE(s.price_index_type, r.price_index_type) AS price_index_type,
    CAST(DATE_TRUNC('MONTH', r.dt_due) AS DATE) AS previous_month_renewal,
    LEAD(CAST(DATE_TRUNC('MONTH', r.dt_due) AS DATE)) OVER (PARTITION BY r.propose ORDER BY r.dt_due, r.ts_created ASC) AS next_month_renewal,
    r.ts_created,
    ROW_NUMBER() OVER (PARTITION BY propose ORDER BY r.ts_created DESC) AS rn
  FROM datalake_rental_guarantee_platform_clean.renewal AS r
  LEFT JOIN datalake_rental_guarantee_platform_clean.legacy_renewal_history AS s
    ON r.id = s.id_renewal
), renewal AS (
  SELECT
    id,
    sk_propose,
    previous_monthly_amount,
    updated_monthly_amount,
    dt_renewal,
    step,
    price_index_type,
    previous_month_renewal,
    ADD_MONTHS(next_month_renewal, -1) AS month_end_renewal,
    ts_created,
    rn
  FROM all_renewal
), first_last_line_renewal AS (
  SELECT
    sk_propose,
    MIN(ts_created) AS min_ts_created
  FROM renewal
  GROUP BY
    1
), first_renewal_value AS (
  SELECT DISTINCT
    r.sk_propose,
    r.previous_monthly_amount AS first_monthly_value_mod,
    r.previous_monthly_amount * 12 AS first_annual_value_mod
  FROM renewal AS r
  INNER JOIN first_last_line_renewal AS fr
    ON r.sk_propose = fr.sk_propose AND r.ts_created = fr.min_ts_created
), all_renewal_corrected AS (
  SELECT DISTINCT
    r.id,
    r.id_propose AS sk_propose,
    r.previous_monthly_amount,
    r.updated_monthly_amount,
    r.dt_due AS dt_renewal,
    r.ts_created AS ts_created,
    CAST(DATE_TRUNC('MONTH', r.dt_due) AS DATE) AS previous_month_renewal,
    LEAD(CAST(DATE_TRUNC('MONTH', r.dt_due) AS DATE)) OVER (PARTITION BY r.id_propose ORDER BY r.dt_due ASC) AS next_month_renewal,
    ROW_NUMBER() OVER (PARTITION BY r.id_propose ORDER BY r.dt_due DESC) AS rn,
    CASE
      WHEN EXTRACT(YEAR FROM dt_due) = 2024
      THEN ADD_MONTHS(DATE_TRUNC('MONTH', r.dt_due), 11)
    END AS dt_final_renewal
  FROM datalake_rental_guarantee_platform_clean.renewal_inconsistencies_corrected AS r
), renewal_corrected AS (
  SELECT
    id,
    sk_propose,
    previous_monthly_amount,
    updated_monthly_amount,
    dt_renewal,
    previous_month_renewal,
    ADD_MONTHS(next_month_renewal, -1) AS month_end_renewal,
    dt_final_renewal,
    ts_created,
    rn
  FROM all_renewal_corrected
), dt_renewal_final AS (
  SELECT DISTINCT
    sk_propose,
    dt_final_renewal
  FROM renewal_corrected
  WHERE
    NOT dt_final_renewal IS NULL
), first_last_line_renewal_corrected AS (
  SELECT
    sk_propose,
    MIN(ts_created) AS min_ts_created
  FROM renewal_corrected
  GROUP BY
    1
), first_renewal_value_corrected AS (
  SELECT DISTINCT
    r.sk_propose,
    r.previous_monthly_amount AS first_monthly_value_mod,
    r.previous_monthly_amount * 12 AS first_annual_value_mod
  FROM renewal_corrected AS r
  INNER JOIN first_last_line_renewal_corrected AS fr
    ON r.sk_propose = fr.sk_propose AND r.ts_created = fr.min_ts_created
), propose_aud AS (
  SELECT
    aud.id AS id_propose,
    p.dt_contract_started,
    monthly_value AS monthly_value_mod,
    aud.annual_value AS annual_value_mod,
    rev.ts_created AS ts_started_mod,
    CAST(rev.ts_created AS DATE) AS dt_started_mod,
    LEAD(CAST(rev.ts_created AS DATE)) OVER (PARTITION BY aud.id ORDER BY rev.ts_created ASC) AS dt_ended_mod,
    ROW_NUMBER() OVER (PARTITION BY aud.id ORDER BY CAST(rev.ts_created AS DATE) ASC) AS ordem_mod
  FROM datalake_rental_guarantee_platform_clean.propose_aud AS aud
  LEFT JOIN datalake_rental_guarantee_platform_clean.rev_info AS rev
    ON aud.rev = rev.rev
  LEFT JOIN dw_velo.fact_velo_propose AS p
    ON aud.id = p.sk_propose
  WHERE
    aud.monthly_value_mod = TRUE
), propose_mod AS (
  SELECT
    p.id_propose,
    dt_contract_started,
    monthly_value_mod,
    annual_value_mod,
    ts_started_mod,
    dt_started_mod,
    dt_ended_mod AS dt_ended_mod_original,
    DATE_TRUNC('MONTH', dt_started_mod) AS month_start_mod,
    DATE_TRUNC('MONTH', ADD_MONTHS(dt_ended_mod, -1)) AS month_ended_mod,
    ordem_mod
  FROM propose_aud AS p
), first_line_propose_aud AS (
  SELECT
    id_propose,
    MIN(ts_started_mod) AS ts_first_start_mod
  FROM propose_mod
  GROUP BY
    1
), first_propose_value AS (
  SELECT DISTINCT
    pm.id_propose,
    pm.monthly_value_mod AS first_monthly_value_mod,
    pm.annual_value_mod AS first_annual_value_mod
  FROM propose_mod AS pm
  INNER JOIN first_line_propose_aud AS f
    ON pm.id_propose = f.id_propose AND pm.ts_started_mod = f.ts_first_start_mod
), corrected_robot AS (
  SELECT DISTINCT
    id_propose AS sk_propose
  FROM datalake_rental_guarantee_platform_clean.renewal_inconsistencies_corrected
), base_propose AS (
  SELECT
    p.sk_propose,
    p.is_direct_billing,
    p.dt_contract_started,
    p.dt_ended_official AS dt_ended,
    IF(
      DAY(TO_DATE(dt_contract_started)) > DAY(TO_DATE(LAST_DAY(p.dt_ended_official))),
      CAST(DATE_ADD(CAST(LAST_DAY(p.dt_ended_official) AS DATE), 5) AS DATE),
      CAST(DATE_ADD(
        CAST(CONCAT(
          CAST(YEAR(TO_DATE(p.dt_ended_official)) AS STRING),
          '-',
          CAST(MONTH(TO_DATE(p.dt_ended_official)) AS STRING),
          '-',
          DAY(TO_DATE(dt_contract_started))
        ) AS DATE),
        5
      ) AS DATE)
    ) AS dt_cancellation_limit,
    IF(pv.monthly_guarantee = 0, omie.monthly_value, pv.monthly_guarantee) AS monthly_guarantee,
    IF(pv.monthly_guarantee = 0, omie.monthly_value * 12, pv.annual_guarantee) AS annual_guarantee,
    pv.monthly_guarantee AS monthly_value_propose,
    pv.annual_guarantee AS annual_value_propose,
    pv.total_package_amount,
    IF(NOT ro.sk_propose IS NULL, TRUE, FALSE) AS is_corrected_robot
  FROM dw_velo.fact_velo_propose AS p
  LEFT JOIN dw_velo.dim_velo_junk AS djk
    ON p.sk_propose_status = djk.sk_junk
  LEFT JOIN dw_velo.dim_velo_propose_values AS pv
    ON p.sk_propose_values = pv.sk_propose_values
  LEFT JOIN mensalidade_omie AS omie
    ON omie.sk_propose = p.sk_propose
  LEFT JOIN corrected_robot AS ro
    ON ro.sk_propose = p.sk_propose
  WHERE
    p.is_contract
    AND djk.desc_lvl_1 <> 'Contrato Assinado mas não pago'
    AND djk.desc_lvl_1 <> 'Proposta Cancelada'
), base_propose_timeline AS (
  SELECT DISTINCT
    dd.month_start,
    b.sk_propose,
    b.is_direct_billing,
    b.dt_contract_started,
    b.dt_ended,
    dt_cancellation_limit,
    MONTHS_BETWEEN(
      COALESCE(DATE_TRUNC('MONTH', b.dt_ended), DATE_TRUNC('MONTH', CURRENT_DATE)),
      DATE_TRUNC('MONTH', b.dt_contract_started)
    ) AS months_life_contract,
    f.first_monthly_value_mod,
    f.first_annual_value_mod,
    CASE
      WHEN DATEDIFF(TO_DATE(b.dt_ended), TO_DATE(b.dt_contract_started)) < 11
      THEN FALSE
      WHEN dd.month_start = DATE_TRUNC('MONTH', dt_ended)
      AND dt_ended <= dt_cancellation_limit
      THEN FALSE
      ELSE TRUE
    END AS month_chargeble,
    COALESCE(
      CASE
        WHEN DATEDIFF(TO_DATE(b.dt_ended), TO_DATE(b.dt_contract_started)) < 11
        THEN 0
        WHEN dd.month_start = DATE_TRUNC('MONTH', dt_ended)
        AND dt_ended <= dt_cancellation_limit
        THEN 0
        WHEN DATE_TRUNC('MONTH', CURRENT_DATE) = DATE_TRUNC('MONTH', r.dt_renewal)
        AND CURRENT_DATE <= r.dt_renewal
        AND NOT r.step IN ('RENEWED', 'DELINQUENCY')
        THEN r.previous_monthly_amount
        WHEN r.dt_renewal > CAST('2024-02-15' AS DATE)
        AND NOT price_index_type IN ('AGREEMENT')
        AND r.previous_monthly_amount > r.updated_monthly_amount
        THEN r.previous_monthly_amount
        WHEN NOT r.step IN ('RENEWED', 'DELINQUENCY')
        THEN COALESCE(
          COALESCE(r.previous_monthly_amount, f.first_monthly_value_mod),
          b.monthly_guarantee
        )
        ELSE COALESCE(COALESCE(r.updated_monthly_amount, f.first_monthly_value_mod), b.monthly_guarantee)
      END,
      0
    ) AS monthly_guarantee_renewal,
    b.is_corrected_robot,
    COALESCE(
      CASE
        WHEN b.is_corrected_robot = FALSE
        THEN NULL
        WHEN dt_final.dt_final_renewal < dd.month_start
        THEN NULL
        WHEN DATEDIFF(TO_DATE(b.dt_ended), TO_DATE(b.dt_contract_started)) < 11
        THEN 0
        WHEN dd.month_start = DATE_TRUNC('MONTH', dt_ended)
        AND dt_ended <= dt_cancellation_limit
        THEN 0
        WHEN DATE_TRUNC('MONTH', CURRENT_DATE) = DATE_TRUNC('MONTH', rc.dt_renewal)
        AND CURRENT_DATE <= rc.dt_renewal
        THEN rc.previous_monthly_amount
        ELSE COALESCE(
          COALESCE(rc.updated_monthly_amount, fc.first_monthly_value_mod),
          b.monthly_guarantee
        )
      END,
      0
    ) AS monthly_guarantee_renewal_corrected,
    COALESCE(
      CASE
        WHEN DATEDIFF(TO_DATE(b.dt_ended), TO_DATE(b.dt_contract_started)) < 11
        THEN 0
        WHEN dd.month_start = DATE_TRUNC('MONTH', dt_ended)
        AND dt_ended <= dt_cancellation_limit
        THEN 0
        ELSE COALESCE(COALESCE(pm.monthly_value_mod, f.first_monthly_value_mod), monthly_value_propose)
      END,
      0
    ) AS monthly_guarantee_propose_aud,
    monthly_value_propose,
    b.annual_guarantee AS annual_value_propose,
    b.total_package_amount,
    CASE
      WHEN dd.month_start < DATE_TRUNC('MONTH', b.dt_ended) OR b.dt_ended IS NULL
      THEN 'ATIVO'
      ELSE 'FINALIZADO'
    END AS status_at_ref,
    CASE
      WHEN dd.month_start <= DATE_TRUNC('MONTH', b.dt_ended) OR b.dt_ended IS NULL
      THEN MONTHS_BETWEEN(dd.month_start, b.dt_contract_started)
      ELSE NULL
    END AS mob_of_life,
    CASE
      WHEN dd.month_start >= DATE_TRUNC('MONTH', b.dt_ended) AND NOT b.dt_ended IS NULL
      THEN MONTHS_BETWEEN(dd.month_start, b.dt_ended)
      ELSE NULL
    END AS mob_of_death
  FROM base_propose AS b
  LEFT JOIN first_renewal_value AS f
    ON b.sk_propose = f.sk_propose
  LEFT JOIN dim_date AS dd
    ON dd.month_start BETWEEN DATE_TRUNC('MONTH', dt_contract_started) AND DATE_TRUNC('MONTH', COALESCE(dt_ended, CURRENT_DATE))
  LEFT JOIN renewal AS r
    ON b.sk_propose = r.sk_propose
    AND b.sk_propose = f.sk_propose
    AND dd.month_start BETWEEN r.previous_month_renewal AND COALESCE(COALESCE(r.month_end_renewal, b.dt_ended), CURRENT_DATE)
  LEFT JOIN first_renewal_value_corrected AS fc
    ON b.sk_propose = fc.sk_propose
  LEFT JOIN renewal_corrected AS rc
    ON b.sk_propose = rc.sk_propose
    AND b.sk_propose = fc.sk_propose
    AND dd.month_start BETWEEN rc.previous_month_renewal AND COALESCE(COALESCE(rc.month_end_renewal, b.dt_ended), rc.dt_final_renewal)
  LEFT JOIN dt_renewal_final AS dt_final
    ON b.sk_propose = dt_final.sk_propose
  LEFT JOIN propose_mod AS pm
    ON b.sk_propose = pm.id_propose
    AND dd.month_start BETWEEN pm.month_start_mod AND COALESCE(COALESCE(pm.month_ended_mod, b.dt_ended), CURRENT_DATE)
)
SELECT
  sk_propose,
  month_start,
  months_life_contract,
  month_chargeble,
  monthly_guarantee_renewal,
  monthly_guarantee_renewal_corrected,
  CASE
    WHEN is_corrected_robot = TRUE AND monthly_guarantee_renewal_corrected = 0
    THEN monthly_guarantee_renewal
    WHEN is_corrected_robot = TRUE AND monthly_guarantee_renewal_corrected > 0
    THEN monthly_guarantee_renewal_corrected
    ELSE monthly_guarantee_renewal
  END AS monthly_guarantee_official,
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
  is_corrected_robot,
  is_direct_billing,
  dt_contract_started,
  dt_ended,
  dt_cancellation_limit,
  NOW() AS ts_load
FROM base_propose_timeline
WHERE
  NOT sk_propose IN (23244, 23245)