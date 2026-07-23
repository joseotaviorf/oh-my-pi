WITH snap_recent AS (
  SELECT
    MAX(CAST(ts_snapshot AS DATE)) AS date_snap_mais_recente
  FROM dw_fintech_snapshot_quintocred.quintocred_payment_full
), dim_date AS (
  SELECT DISTINCT
    month_start,
    month_end,
    year
  FROM dw_public.dim_date
), snap AS (
  SELECT
    s.*,
    r.date_snap_mais_recente,
    CAST(s.ts_snapshot AS DATE) AS dt_snapshot,
    dt.month_start,
    dt.month_end
  FROM dw_fintech_snapshot_quintocred.quintocred_payment_full AS s
  LEFT JOIN dim_date AS dt
    ON dt.month_start = ADD_MONTHS(DATE_TRUNC('MONTH', CAST(s.ts_snapshot AS DATE)), -1)
  JOIN snap_recent AS r
    ON CAST(s.ts_snapshot AS DATE) = r.date_snap_mais_recente
  WHERE
    dt.month_start >= CAST('2025-02-01' AS DATE)
), propose_person AS (
  SELECT
    sk_propose,
    name,
    cpf,
    cnpj,
    subscription_type
  FROM (
    SELECT DISTINCT
      p.sk_propose,
      pp.name,
      pp.document AS cpf,
      dvc.cnpj,
      pv.subscription_type,
      ROW_NUMBER() OVER (PARTITION BY sk_propose ORDER BY pp.declared_income DESC) AS _w,
      pp.declared_income
    FROM dw_velo.fact_velo_propose AS p
    LEFT JOIN dw_velo.dim_velo_propose_person AS pp
      ON p.sk_primary_person = pp.sk_person
    LEFT JOIN dw_velo.dim_velo_propose_company AS dvc
      ON p.sk_propose_company = dvc.sk_company
    LEFT JOIN dw_velo.dim_velo_propose_values AS pv
      ON p.sk_propose_values = pv.sk_propose_values
    WHERE
      p.is_contract
  ) AS _t
  WHERE
    _w = 1
), renewal_current_year AS (
  SELECT DISTINCT
    r.propose AS sk_propose,
    dt_due AS dt_renewal,
    step,
    CAST(DATE_TRUNC('MONTH', dt_due) AS DATE) AS month_renewal,
    ts_created,
    ROW_NUMBER() OVER (PARTITION BY propose ORDER BY ts_created DESC) AS rn_renewal
  FROM datalake_rental_guarantee_platform_clean.renewal AS r
  WHERE
    DATE_TRUNC('YEAR', r.dt_due) = DATE_TRUNC('YEAR', CURRENT_DATE)
), propose_timeline_renewal AS (
  SELECT
    *,
    CASE
      WHEN TRY_CAST(CONCAT(
        CAST(YEAR(TO_DATE(CURRENT_DATE)) AS STRING),
        '-',
        CAST(MONTH(TO_DATE(dt_contract_started)) AS STRING),
        '-',
        CAST(DAY(TO_DATE(dt_contract_started)) AS STRING)
      ) AS DATE) IS NULL
      THEN DATE_TRUNC(
        'MONTH',
        CAST(CONCAT(
          CAST(YEAR(TO_DATE(CURRENT_DATE)) AS STRING),
          '-',
          CAST(MONTH(TO_DATE(dt_contract_started)) AS STRING),
          '-',
          CAST(DAY(TO_DATE(dt_contract_started)) - 1 AS STRING)
        ) AS DATE)
      )
      ELSE DATE_TRUNC(
        'MONTH',
        CAST(CONCAT(
          CAST(YEAR(TO_DATE(CURRENT_DATE)) AS STRING),
          '-',
          CAST(MONTH(TO_DATE(dt_contract_started)) AS STRING),
          '-',
          CAST(DAY(TO_DATE(dt_contract_started)) AS STRING)
        ) AS DATE)
      )
    END AS month_renewal_backup,
    CASE
      WHEN is_corrected_robot = TRUE AND monthly_timeline_renewal_corrected = 0
      THEN monthly_timeline_renewal
      WHEN is_corrected_robot = TRUE AND monthly_timeline_renewal_corrected > 0
      THEN monthly_timeline_renewal_corrected
      ELSE monthly_timeline_renewal
    END AS monthly_timeline_renewal_adj
  FROM snap
), mensalidades_renewal AS (
  SELECT DISTINCT
    tl.sk_propose,
    IF(
      (
        tl.month_propose_life < COALESCE(r.month_renewal, tl.month_renewal_backup)
        OR r.sk_propose IS NULL
      ),
      tl.monthly_timeline_renewal_adj,
      0
    ) AS monthly_guarantee_before_renewal,
    IF(
      tl.month_propose_life >= COALESCE(r.month_renewal, tl.month_renewal_backup),
      tl.monthly_timeline_renewal_adj,
      0
    ) AS monthly_guarantee_after_renewal
  FROM propose_timeline_renewal AS tl
  LEFT JOIN renewal_current_year AS r
    ON tl.sk_propose = CAST(r.sk_propose AS STRING)
  WHERE
    month_propose_life >= CAST(CONCAT(CAST(YEAR(TO_DATE(CURRENT_DATE)) - 1 AS STRING), '-12-01') AS DATE)
), mensalidades_renewal_deduplicada AS (
  SELECT
    sk_propose,
    MAX(monthly_guarantee_before_renewal) AS monthly_guarantee_before_renewal,
    MAX(monthly_guarantee_after_renewal) AS monthly_guarantee_after_renewal
  FROM mensalidades_renewal
  GROUP BY
    1
  ORDER BY
    1
), mensalidades_propose_aud AS (
  SELECT
    month_reference,
    sk_propose,
    monthly_timeline_propose_aud AS monthly_guarantee_before_aud,
    LEAD(monthly_timeline_propose_aud) OVER (PARTITION BY sk_propose ORDER BY month_reference) AS monthly_guarantee_after_aud
  FROM snap
  WHERE
    month_chargeble = TRUE
), mensalidades_propose_aud_order AS (
  SELECT
    sk_propose,
    month_reference,
    monthly_guarantee_before_aud,
    monthly_guarantee_after_aud
  FROM (
    SELECT
      sk_propose,
      month_reference,
      monthly_guarantee_before_aud,
      monthly_guarantee_after_aud,
      ROW_NUMBER() OVER (PARTITION BY sk_propose ORDER BY month_reference DESC) AS _w
    FROM mensalidades_propose_aud
    WHERE
      monthly_guarantee_before_aud <> monthly_guarantee_after_aud
  ) AS _t
  WHERE
    _w = 1
), modalidade_cobranca AS (
  SELECT
    sk_propose,
    month_reference,
    gateway_payment,
    monthly_timeline_renewal,
    monthly_timeline_propose_aud,
    monthly_value_propose,
    delinquency_monthly_value,
    value_payment
  FROM (
    SELECT
      sk_propose,
      month_reference,
      gateway_payment,
      monthly_timeline_renewal,
      monthly_timeline_propose_aud,
      monthly_value_propose,
      delinquency_monthly_value,
      value AS value_payment,
      ROW_NUMBER() OVER (PARTITION BY sk_propose ORDER BY month_reference DESC) AS _w
    FROM snap AS tl
    WHERE
      NOT month_propose_life IS NULL
      AND tl.month_chargeble = TRUE
      AND NOT gateway_final IN ('vivendo de graça')
      AND month_reference < DATE_TRUNC('MONTH', CURRENT_DATE)
  ) AS _t
  WHERE
    _w = 1
), base_final AS (
  SELECT
    tl.sk_propose,
    CASE
      WHEN ABS(mod.monthly_timeline_renewal - mod.monthly_value_propose) < 0.2
      AND ABS(mod.monthly_timeline_renewal - mod.value_payment) < 0.2
      AND ABS(mod.monthly_timeline_renewal - mod.delinquency_monthly_value) < 0.2
      THEN 'Match completo - PAY=D=R=PR'
      WHEN ABS(mod.monthly_timeline_renewal - mod.monthly_value_propose) < 0.2
      AND ABS(mod.monthly_timeline_renewal - mod.value_payment) < 0.2
      AND mod.delinquency_monthly_value IS NULL
      THEN 'Match completo - PAY=R=PR'
      WHEN ABS(mod.monthly_timeline_renewal - mod.monthly_value_propose) < 0.2
      AND ABS(mod.monthly_timeline_renewal - mod.delinquency_monthly_value) < 0.2
      AND mod.value_payment IS NULL
      THEN 'Match completo - D=R=PR'
      WHEN ABS(mod.monthly_timeline_renewal - mod.monthly_value_propose) < 0.2
      AND ABS(mod.monthly_timeline_renewal - mod.value_payment) < 0.2
      AND NOT mod.delinquency_monthly_value IS NULL
      THEN 'Match parcial - D<>PAY=R=PR'
      WHEN ABS(mod.monthly_timeline_renewal - mod.monthly_value_propose) < 0.2
      AND ABS(mod.monthly_timeline_renewal - mod.delinquency_monthly_value) < 0.2
      AND NOT mod.value_payment IS NULL
      THEN 'Match parcial - PAY<>D=R=PR'
      WHEN ABS(mod.delinquency_monthly_value - mod.monthly_timeline_renewal) < 0.2
      AND ABS(mod.value_payment - mod.monthly_timeline_renewal) < 0.2
      THEN 'Match parcial - PAY=D=R<>PR'
      WHEN ABS(mod.value_payment - mod.monthly_timeline_renewal) < 0.2
      AND mod.delinquency_monthly_value IS NULL
      THEN 'Match parcial - PAY=R<>PR'
      WHEN ABS(mod.value_payment - mod.monthly_timeline_renewal) < 0.2
      AND NOT mod.delinquency_monthly_value IS NULL
      THEN 'Match parcial - D<>PAY=R<>PR'
      WHEN ABS(mod.delinquency_monthly_value - mod.monthly_timeline_renewal) < 0.2
      AND NOT mod.value_payment IS NULL
      THEN 'Match parcial - PAY<>D=R<>PR'
      WHEN ABS(mod.delinquency_monthly_value - mod.monthly_timeline_renewal) < 0.2
      AND mod.value_payment IS NULL
      THEN 'Match parcial - D=R<>PR'
      WHEN ABS(mod.delinquency_monthly_value - mod.monthly_value_propose) < 0.2
      AND ABS(mod.value_payment - mod.monthly_value_propose) < 0.2
      THEN 'Match parcial - PAY=D=PR<>R'
      WHEN ABS(mod.value_payment - mod.monthly_value_propose) < 0.2
      AND mod.delinquency_monthly_value IS NULL
      THEN 'Match parcial - PAY=PR<>R'
      WHEN ABS(mod.value_payment - mod.monthly_value_propose) < 0.2
      AND NOT mod.delinquency_monthly_value IS NULL
      THEN 'Match parcial - D<>PAY=PR<>R'
      WHEN ABS(mod.delinquency_monthly_value - mod.monthly_value_propose) < 0.2
      AND NOT mod.value_payment IS NULL
      THEN 'Match parcial - PAY<>D=PR<>R'
      WHEN ABS(mod.delinquency_monthly_value - mod.monthly_value_propose) < 0.2
      AND mod.value_payment IS NULL
      THEN 'Match parcial - D=PR<>R'
      WHEN ABS(mod.monthly_value_propose - mod.monthly_timeline_renewal) < 0.2
      THEN 'Match parcial - D<>PAY<>PR=R'
      ELSE 'No match D<>PAY<>R<>PR'
    END AS match_status,
    pp.name AS client_name,
    COALESCE(cnpj, cpf) AS cpf_cnpj,
    tl.dt_contract_started,
    tl.dt_ended,
    IF(mod.gateway_payment = 'BILLING DIRETO', 'BILLING DIRETO', 'QUINTOCRED COBRA') AS modalidade_cobranca,
    COUNT(IF(tl.gateway_payment = 'BILLING DIRETO', tl.monthly_timeline_renewal, NULL)) AS months_billing_direto,
    COUNT(
      IF(
        NOT tl.gateway_payment IN ('BILLING DIRETO', 'sem cobrança'),
        tl.monthly_timeline_renewal,
        NULL
      )
    ) AS months_quintocred_cobra,
    COALESCE(r.month_renewal, tl.month_renewal_backup) AS month_renewal,
    COUNT(IF(tl.month_chargeble = TRUE, tl.month_propose_life, NULL)) AS total_months_of_service,
    SUM(tl.monthly_timeline_renewal_adj) AS expected_revenue_renewal,
    COUNT(
      CASE
        WHEN tl.month_propose_life < COALESCE(r.month_renewal, tl.month_renewal_backup)
        AND tl.month_chargeble = TRUE
        THEN tl.month_propose_life
      END
    ) AS months_before_renewal,
    m.monthly_guarantee_before_renewal,
    COUNT(
      CASE
        WHEN tl.month_propose_life >= COALESCE(r.month_renewal, tl.month_renewal_backup)
        AND tl.month_chargeble = TRUE
        THEN tl.month_propose_life
      END
    ) AS months_after_renewal,
    m.monthly_guarantee_after_renewal,
    SUM(COALESCE(tl.monthly_timeline_propose_aud, 0)) AS expected_revenue_aud,
    aud.month_reference AS month_update_aud,
    aud.monthly_guarantee_before_aud,
    aud.monthly_guarantee_after_aud,
    mod.value_payment,
    mod.delinquency_monthly_value,
    tl.month_start AS month_closing,
    tl.dt_snapshot
  FROM propose_timeline_renewal AS tl
  LEFT JOIN modalidade_cobranca AS mod
    ON tl.sk_propose = mod.sk_propose
  LEFT JOIN mensalidades_renewal_deduplicada AS m
    ON tl.sk_propose = m.sk_propose
  LEFT JOIN mensalidades_propose_aud_order AS aud
    ON tl.sk_propose = aud.sk_propose
  LEFT JOIN propose_person AS pp
    ON tl.sk_propose = CAST(pp.sk_propose AS STRING)
  LEFT JOIN renewal_current_year AS r
    ON tl.sk_propose = CAST(r.sk_propose AS STRING) AND rn_renewal = 1
  WHERE
    EXTRACT(YEAR FROM tl.month_propose_life) = EXTRACT(YEAR FROM CURRENT_DATE)
    AND tl.month_propose_life < DATE_TRUNC('MONTH', CURRENT_DATE)
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    10,
    14,
    16,
    18,
    19,
    20,
    21,
    22,
    23,
    24
)
SELECT
  sk_propose,
  match_status,
  client_name,
  cpf_cnpj,
  modalidade_cobranca AS billing_method,
  months_billing_direto,
  months_quintocred_cobra,
  total_months_of_service,
  expected_revenue_renewal,
  months_before_renewal,
  monthly_guarantee_before_renewal,
  months_after_renewal,
  monthly_guarantee_after_renewal,
  expected_revenue_aud,
  monthly_guarantee_before_aud,
  monthly_guarantee_after_aud,
  value_payment,
  delinquency_monthly_value,
  month_renewal AS dt_month_renewal,
  month_update_aud AS dt_month_update_aud,
  dt_contract_started,
  dt_ended,
  month_closing AS dt_month_closing,
  dt_snapshot
FROM base_final
WHERE
  (
    expected_revenue_renewal > 0 OR expected_revenue_aud > 0
  )
