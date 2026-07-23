WITH invoice_closing_date AS (
  SELECT DISTINCT
    c.id_external AS sk_contract,
    CAST(c.ts_charge_started AS DATE) AS dt_started,
    i.accrual_year_month AS invoice_accrual_year_month,
    MAX(e.ts_created) AS ts_created
  FROM datalake_retsuko.invoice AS i
  INNER JOIN datalake_retsuko.entry AS e
    ON i.id = e.id_invoice
  INNER JOIN datalake_retsuko_clean.contract AS c
    ON i.id_contract = c.id
  WHERE
    i.purpose = 'monthly'
    AND SPLIT(e.bill_item, 'entry.bill-item/')[1] IN ('adm-fee', 'adjustment-agreement-adm-fee', 'adjustment-agreement-adm-partner-adm-fee', 'adm-fee-adm-partner', 'igpm-adm-fee', 'igpm-adm-partner-adm-fee', 'ipca-adm-fee', 'ipca-adm-partner-adm-fee')
    AND i.status <> 'canceled'
    AND c.status IN ('active', 'ended')
    AND c.country_code = 'BR'
  GROUP BY
    1,
    2,
    3
), rent_at_closing_moment AS (
  SELECT
    id_contract,
    rent,
    ts_invoice_created,
    rev_accrual_year_month,
    invoice_accrual_year_month,
    invoice_year,
    invoice_month,
    dt_started,
    dt_year_started,
    dt_month_started,
    dt_day_started,
    dt_ended,
    rn
  FROM (
    SELECT
      ca.id_contract,
      ca.rent,
      dt.ts_created AS ts_invoice_created,
      CAST(YEAR(TO_DATE(FROM_UNIXTIME(ROUND(ur.ts_revision / 1000.0)))) || LPAD(MONTH(TO_DATE(FROM_UNIXTIME(ROUND(ur.ts_revision / 1000.0)))), 2, '0') AS INT) AS rev_accrual_year_month,
      CAST(dt.invoice_accrual_year_month AS INT) AS invoice_accrual_year_month,
      CAST(LEFT(dt.invoice_accrual_year_month, 4) AS INT) AS invoice_year,
      CAST(RIGHT(dt.invoice_accrual_year_month, 2) AS INT) AS invoice_month,
      ca.dt_started,
      YEAR(TO_DATE(ca.dt_started)) AS dt_year_started,
      MONTH(TO_DATE(ca.dt_started)) AS dt_month_started,
      DAY(TO_DATE(ca.dt_started)) AS dt_day_started,
      CAST(COALESCE(COALESCE(ca.dt_termination, c.dt_termination), c.ts_expected_termination) AS DATE) AS dt_ended,
      ROW_NUMBER() OVER (PARTITION BY ca.id_contract, dt.invoice_accrual_year_month ORDER BY rev DESC) AS rn,
      ROW_NUMBER() OVER (PARTITION BY ca.id_contract, CAST(dt.invoice_accrual_year_month AS INT) ORDER BY rev DESC) AS _w,
      rev
    FROM datalake_ebdb_clean.contract_aud AS ca
    INNER JOIN datalake_ebdb_clean.user_revision_entity AS ur
      ON ca.rev = ur.id
    INNER JOIN datalake_ebdb_contract.contract AS c
      ON c.id = ca.id_contract
    INNER JOIN invoice_closing_date AS dt
      ON dt.sk_contract = ca.id_contract
    WHERE
      CAST(FROM_UNIXTIME(ROUND(ur.ts_revision / 1000.0)) AS TIMESTAMP) <= dt.ts_created
      AND CAST(YEAR(TO_DATE(FROM_UNIXTIME(ROUND(ur.ts_revision / 1000.0)))) || LPAD(MONTH(TO_DATE(FROM_UNIXTIME(ROUND(ur.ts_revision / 1000.0)))), 2, '0') AS INT) <= CAST(dt.invoice_accrual_year_month AS INT)
  ) AS _t
  WHERE
    _w = 1
), rent_at_closing_moment_2 AS (
  SELECT
    id_contract,
    rent,
    LAG(rent, 1, rent) OVER (PARTITION BY id_contract ORDER BY invoice_accrual_year_month) AS previous_rent,
    1.00 - (
      rent / LAG(rent, 1, rent) OVER (PARTITION BY id_contract ORDER BY invoice_accrual_year_month)
    ) AS readjustment_perc,
    ts_invoice_created,
    dd.total_days_in_month,
    dd.days_until_end_of_month,
    rev_accrual_year_month,
    invoice_accrual_year_month,
    invoice_year,
    invoice_month,
    dt_started,
    dt_year_started,
    dt_month_started,
    dt_day_started,
    CAST(invoice_year || '-' || LPAD(dt_month_started, 2, '0') || '-' || LPAD(dt_day_started, 2, '0') AS DATE) AS dt_reference,
    dt_ended,
    IF(invoice_month = dt_month_started AND invoice_year > dt_year_started, TRUE, FALSE) AS is_birthday_month,
    rn
  FROM rent_at_closing_moment AS r
  INNER JOIN dw_public.dim_date AS dd
    ON dd.date = CAST(invoice_year || '-' || LPAD(dt_month_started, 2, '0') || '-' || LPAD(dt_day_started, 2, '0') AS DATE)
), rent_at_closing_moment_3 AS (
  SELECT
    id_contract,
    ROUND(rent, 2) AS rent,
    ROUND(previous_rent, 2) AS previous_rent,
    CASE
      WHEN is_birthday_month IS TRUE
      AND DAY(TO_DATE(dt_ended)) < dt_day_started
      AND MONTH(TO_DATE(dt_ended)) = dt_month_started
      THEN previous_rent / total_days_in_month * (
        DATEDIFF(TO_DATE(dt_ended), TO_DATE(DATE_TRUNC('MONTH', dt_ended))) + 1
      )
      WHEN is_birthday_month IS TRUE
      THEN previous_rent + (
        (
          rent - previous_rent
        ) / total_days_in_month * (
          days_until_end_of_month + 1
        )
      )
      ELSE rent
    END AS rent_adjusted,
    ROUND(readjustment_perc, 6) AS readjustment_perc,
    ts_invoice_created,
    total_days_in_month,
    days_until_end_of_month,
    invoice_accrual_year_month,
    invoice_year,
    invoice_month,
    dt_started,
    dt_year_started,
    dt_month_started,
    dt_day_started,
    dt_reference,
    dt_ended,
    is_birthday_month,
    IF(
      is_birthday_month IS TRUE
      AND DAY(TO_DATE(dt_ended)) < dt_day_started
      AND MONTH(TO_DATE(dt_ended)) = dt_month_started,
      TRUE,
      FALSE
    ) AS ended_before_birthday
  FROM rent_at_closing_moment_2
), adm_at_closing_moment AS (
  SELECT
    id,
    dt_started,
    promotional_period,
    accrual_promotional_ended,
    invoice_accrual_year_month,
    adm_fee_charge_type,
    standard_administration_fee,
    minimum_fee_value,
    promotional_adm_fee,
    monthly_administration_fee
  FROM (
    SELECT
      ca.id,
      dt_started,
      ca.promotional_period,
      IF(
        ca.promotional_period > 0,
        LEFT(REPLACE(ADD_MONTHS(dt.dt_started, ca.promotional_period), '-', ''), 6),
        NULL
      ) AS accrual_promotional_ended,
      invoice_accrual_year_month,
      ca.adm_fee_charge_type,
      ROUND(ca.monthly_administration_fee, 4) AS standard_administration_fee,
      COALESCE(ca.minimum_fee_value, 0.00) AS minimum_fee_value,
      ROUND(ca.promotional_adm_fee, 4) AS promotional_adm_fee,
      IF(
        CAST(LEFT(REPLACE(ADD_MONTHS(dt.dt_started, ca.promotional_period), '-', ''), 6) AS INT) >= invoice_accrual_year_month
        AND ca.promotional_period > 0,
        ROUND(ca.promotional_adm_fee, 4),
        ROUND(ca.monthly_administration_fee, 4)
      ) AS monthly_administration_fee,
      ROW_NUMBER() OVER (PARTITION BY ca.id, invoice_accrual_year_month ORDER BY rev DESC) AS _w,
      rev
    FROM datalake_ebdb_clean.full_contract_aud AS ca
    LEFT JOIN datalake_ebdb_clean.user_revision_entity AS ur
      ON ca.rev = ur.id
    LEFT JOIN invoice_closing_date AS dt
      ON dt.sk_contract = ca.id
    WHERE
      CAST(FROM_UNIXTIME(ROUND(ur.ts_revision / 1000.0)) AS TIMESTAMP) <= dt.ts_created
  ) AS _t
  WHERE
    _w = 1
), df AS (
  SELECT
    i.sk_contract AS id_contract,
    a.adm_fee_charge_type,
    a.monthly_administration_fee,
    a.standard_administration_fee,
    a.minimum_fee_value,
    a.promotional_adm_fee,
    a.promotional_period,
    accrual_promotional_ended,
    r.rent,
    r.previous_rent,
    r.rent_adjusted,
    r.readjustment_perc,
    ROUND(
      CASE
        WHEN is_birthday_month IS TRUE
        AND ended_before_birthday IS FALSE
        AND i.invoice_accrual_year_month = SUBSTRING(REPLACE(r.dt_ended, '-', ''), 1, 6)
        THEN (
          (
            r.previous_rent / dd_end.total_days_in_month * DATEDIFF(TO_DATE(r.dt_reference), TO_DATE(DATE_TRUNC('MONTH', r.dt_reference)))
          ) + (
            r.rent / dd_end.total_days_in_month * (
              DATEDIFF(TO_DATE(r.dt_ended), TO_DATE(r.dt_reference)) + 1
            )
          )
        ) * a.monthly_administration_fee
        WHEN a.adm_fee_charge_type IN ('FromFirstMonthWithBrokerage', 'FromFirstMonth')
        AND i.invoice_accrual_year_month = SUBSTRING(REPLACE(r.dt_started, '-', ''), 1, 6)
        AND i.invoice_accrual_year_month = SUBSTRING(REPLACE(r.dt_ended, '-', ''), 1, 6)
        THEN (
          r.rent_adjusted / dd.total_days_in_month * (
            DATEDIFF(TO_DATE(r.dt_ended), TO_DATE(r.dt_started)) + 1
          ) * a.monthly_administration_fee
        )
        WHEN a.adm_fee_charge_type IN ('FromFirstMonthWithBrokerage', 'FromFirstMonth')
        AND i.invoice_accrual_year_month = SUBSTRING(REPLACE(r.dt_started, '-', ''), 1, 6)
        THEN (
          r.rent_adjusted / dd.total_days_in_month * (
            dd.days_until_end_of_month + 1
          ) * a.monthly_administration_fee
        )
        WHEN a.adm_fee_charge_type = 'FromSecondMonth'
        AND i.invoice_accrual_year_month = SUBSTRING(REPLACE(dd_second.date, '-', ''), 1, 6)
        AND i.invoice_accrual_year_month = SUBSTRING(REPLACE(r.dt_ended, '-', ''), 1, 6)
        THEN (
          r.rent_adjusted / dd.total_days_in_month * (
            DATEDIFF(TO_DATE(r.dt_ended), TO_DATE(r.dt_started)) + 1
          ) * a.monthly_administration_fee
        )
        WHEN a.adm_fee_charge_type = 'FromSecondMonth'
        AND (
          CAST(i.invoice_accrual_year_month AS INT)
        ) = CAST(SUBSTRING(REPLACE(dd_second.date, '-', ''), 1, 6) AS INT)
        THEN (
          r.rent_adjusted / dd_second.total_days_in_month * (
            dd_second.days_until_end_of_month + 1
          ) * a.monthly_administration_fee
        )
        WHEN i.invoice_accrual_year_month = SUBSTRING(REPLACE(r.dt_ended, '-', ''), 1, 6)
        AND ended_before_birthday IS FALSE
        THEN (
          r.rent_adjusted / dd_end.total_days_in_month * (
            dd_end.days_since_beginning_of_month + 1
          ) * a.monthly_administration_fee
        )
        WHEN is_birthday_month IS FALSE
        THEN r.previous_rent * a.monthly_administration_fee
        ELSE r.rent_adjusted * a.monthly_administration_fee
      END,
      2
    ) AS adm_fee,
    ROUND(
      CASE
        WHEN a.adm_fee_charge_type IN ('FromFirstMonthWithBrokerage', 'FromFirstMonth')
        AND i.invoice_accrual_year_month = SUBSTRING(REPLACE(r.dt_started, '-', ''), 1, 6)
        AND i.invoice_accrual_year_month = SUBSTRING(REPLACE(r.dt_ended, '-', ''), 1, 6)
        THEN (
          a.minimum_fee_value / dd.total_days_in_month * (
            DATEDIFF(TO_DATE(r.dt_ended), TO_DATE(r.dt_started)) + 1
          )
        )
        WHEN a.adm_fee_charge_type IN ('FromFirstMonthWithBrokerage', 'FromFirstMonth')
        AND i.invoice_accrual_year_month = SUBSTRING(REPLACE(r.dt_started, '-', ''), 1, 6)
        THEN (
          a.minimum_fee_value / dd.total_days_in_month * (
            dd.days_until_end_of_month + 1
          )
        )
        WHEN a.adm_fee_charge_type = 'FromSecondMonth'
        AND i.invoice_accrual_year_month = SUBSTRING(REPLACE(dd_second.date, '-', ''), 1, 6)
        AND i.invoice_accrual_year_month = SUBSTRING(REPLACE(r.dt_ended, '-', ''), 1, 6)
        THEN (
          a.minimum_fee_value / dd.total_days_in_month * (
            DATEDIFF(TO_DATE(r.dt_ended), TO_DATE(r.dt_started)) + 1
          )
        )
        WHEN a.adm_fee_charge_type = 'FromSecondMonth'
        AND (
          CAST(i.invoice_accrual_year_month AS INT)
        ) = CAST(SUBSTRING(REPLACE(dd_second.date, '-', ''), 1, 6) AS INT)
        THEN (
          a.minimum_fee_value / dd_second.total_days_in_month * (
            dd_second.days_until_end_of_month + 1
          )
        )
        WHEN i.invoice_accrual_year_month = SUBSTRING(REPLACE(r.dt_ended, '-', ''), 1, 6)
        THEN (
          a.minimum_fee_value / dd_end.total_days_in_month * (
            dd_end.days_since_beginning_of_month + 1
          )
        )
        WHEN is_birthday_month IS FALSE
        THEN a.minimum_fee_value
        ELSE a.minimum_fee_value
      END,
      2
    ) AS adm_fee_min,
    i.invoice_accrual_year_month,
    IF(
      a.adm_fee_charge_type IN ('FromFirstMonthWithBrokerage', 'FromFirstMonth')
      AND i.invoice_accrual_year_month = SUBSTRING(REPLACE(r.dt_started, '-', ''), 1, 6)
      OR a.adm_fee_charge_type = 'FromSecondMonth'
      AND (
        CAST(i.invoice_accrual_year_month AS INT)
      ) = CAST(SUBSTRING(REPLACE(dd_second.date, '-', ''), 1, 6) AS INT),
      TRUE,
      FALSE
    ) AS is_contract_start_month,
    IF(
      i.invoice_accrual_year_month = SUBSTRING(REPLACE(r.dt_ended, '-', ''), 1, 6),
      TRUE,
      FALSE
    ) AS is_contract_closing_month,
    r.is_birthday_month,
    r.ended_before_birthday,
    r.dt_started AS dt_contract_started,
    r.dt_ended AS dt_contract_ended
  FROM invoice_closing_date AS i
  LEFT JOIN rent_at_closing_moment_3 AS r
    ON i.sk_contract = r.id_contract
    AND i.invoice_accrual_year_month = r.invoice_accrual_year_month
  LEFT JOIN adm_at_closing_moment AS a
    ON i.sk_contract = a.id
    AND i.invoice_accrual_year_month = a.invoice_accrual_year_month
  LEFT JOIN dw_public.dim_date AS dd
    ON dd.date = r.dt_started
    AND a.adm_fee_charge_type IN ('FromFirstMonthWithBrokerage', 'FromFirstMonth')
  LEFT JOIN dw_public.dim_date AS dd_second
    ON dd_second.date = ADD_MONTHS(r.dt_started, 1)
    AND a.adm_fee_charge_type = 'FromSecondMonth'
  LEFT JOIN dw_public.dim_date AS dd_end
    ON dd_end.date = r.dt_ended
  WHERE
    i.invoice_accrual_year_month >= 202401
)
SELECT DISTINCT
  id_contract,
  adm_fee_charge_type,
  rent,
  IF(adm_fee > adm_fee_min, adm_fee, adm_fee_min) AS adm_fee,
  previous_rent,
  rent_adjusted,
  readjustment_perc,
  standard_administration_fee,
  minimum_fee_value,
  promotional_adm_fee,
  promotional_period,
  accrual_promotional_ended AS promotional_ended_accrual_year_month,
  invoice_accrual_year_month,
  is_contract_start_month,
  is_contract_closing_month,
  is_birthday_month,
  ended_before_birthday AS has_ended_before_birthday,
  dt_contract_started,
  dt_contract_ended
FROM df
