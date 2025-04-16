WITH cte_salaries AS (
  SELECT
    id_assignment,
    action_code,
    action_reason,
    salary_amount,
    salary_range_mid_point,
    adjustment_amount,
    adjustment_percentage,
    currency_code,
    UPPER(action_reason_code) LIKE 'DISSÍDIO%' AS is_collective_wage_adjustment,
    ROW_NUMBER() OVER (
      PARTITION BY id_assignment
      ORDER BY
        dt_from ASC
    ) AS salary_asc_order,
    ROW_NUMBER() OVER (
      PARTITION BY id_assignment
      ORDER BY
        dt_from DESC
    ) AS salary_desc_order,
    ROW_NUMBER() OVER (
      PARTITION BY id_assignment,
      action_code
      ORDER BY
        dt_from ASC
    ) AS salary_and_action_asc_order,
    dt_from
  FROM
    datalake_hr_system_clean.salaries
  WHERE
    dt_from <= DATE('{load_end_date}')
),
cte_first_salary_and_promotions AS (
  SELECT
    id_assignment,
    salary_amount,
    dt_from
  FROM
    datalake_hr_system_clean.salaries
  WHERE
    dt_from <= DATE('{load_end_date}')
  QUALIFY ROW_NUMBER() OVER (
      PARTITION BY id_assignment
      ORDER BY
        dt_from
    ) = 1
  UNION
  SELECT
    id_assignment,
    salary_amount,
    dt_from
  FROM
    datalake_hr_system_clean.salaries
  WHERE
    action_code = 'PROMOTION'
    AND dt_from <= DATE('{load_end_date}')
),
cte_time_between_promotions AS (
  SELECT
    id_assignment,
    dt_from AS salary_date,
    LEAD(dt_from) OVER (
      PARTITION BY id_assignment
      ORDER BY
        dt_from
    ) AS next_promotion_date,
    DATEDIFF(MONTH, salary_date, next_promotion_date) AS time_between_movimentations
  FROM
    cte_first_salary_and_promotions
),
cte_promotion_metrics AS (
  SELECT
    id_assignment,
    AVG(time_between_movimentations) AS average_time_between_movimentations
  FROM
    cte_time_between_promotions
  GROUP BY
    id_assignment
),
exchange_rates AS (
  SELECT
    currency_from,
    bid_price AS conversion_rate
  FROM
    datalake_awesomeapi_currency_rates_clean.currency_closing_rates
  WHERE
    currency_to = 'BRL'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY currency_from ORDER BY dt_created DESC) = 1
)

SELECT
  cs.id_assignment,
  REPLACE(
    MAX(cs.dt_from) FILTER (
      WHERE
        NOT cs.is_collective_wage_adjustment
    ),
    '-',
    ''
  ) AS sk_last_increase_date,
  REPLACE(
    MIN(cs.dt_from) FILTER (
      WHERE
        cs.action_code = 'PROMOTION'
    ),
    '-',
    ''
  ) AS sk_first_promotion_date,
  MAX(cs.currency_code) FILTER (
    WHERE
      cs.salary_desc_order = 1
  ) AS currency_code,
  COUNT(1) FILTER (
    WHERE
      cs.action_code = 'PROMOTION'
  ) AS qnt_promotions,
  COUNT(1) FILTER (
    WHERE
      NOT cs.is_collective_wage_adjustment
  ) AS qnt_movimentations,
  MAX(cs.salary_amount) FILTER (
    WHERE
      cs.salary_desc_order = 1
  ) AS current_salary_amount,
  current_salary_amount * IF(cs.currency_code <> 'BRL', er.conversion_rate, 1) AS current_salary_amount_brl,
  MAX(cs.salary_amount) FILTER (
    WHERE
      cs.salary_asc_order = 1
  ) AS first_salary_amount,
  MAX(cs.salary_amount) FILTER (
    WHERE
      cs.salary_desc_order <> 1
      AND NOT cs.is_collective_wage_adjustment
  ) AS previous_salary_amount,
  MAX(cs.salary_range_mid_point) FILTER (
    WHERE
      cs.salary_desc_order = 1
  ) AS salary_reference,
  MIN(cs.adjustment_amount) FILTER (
    WHERE
      NOT cs.is_collective_wage_adjustment
  ) AS last_salary_increase,
  MAX(cs.adjustment_percentage) FILTER (
    WHERE
      NOT cs.is_collective_wage_adjustment
  ) AS pct_last_salary_increase,
  current_salary_amount - first_salary_amount AS range_salary_movement,
  MIN(cs.salary_amount) FILTER (
    WHERE
      cs.action_code = 'PROMOTION'
      AND salary_and_action_asc_order = 1
  ) AS first_promotion_salary,
  MIN(cs.adjustment_amount) FILTER (
    WHERE
      cs.action_code = 'PROMOTION'
      AND salary_and_action_asc_order = 1
  ) AS nominal_increase_first_promotion,
  MIN(cs.adjustment_percentage) FILTER (
    WHERE
      cs.action_code = 'PROMOTION'
      AND salary_and_action_asc_order = 1
  ) AS pct_increase_first_promotion,
  MAX(cpm.average_time_between_movimentations) AS average_time_between_movimentations,
  MIN(cs.dt_from) FILTER (
    WHERE
      cs.action_code = 'PROMOTION'
  ) AS dt_first_promotion
FROM
  cte_salaries AS cs
LEFT JOIN
  cte_promotion_metrics AS cpm
    ON cpm.id_assignment = cs.id_assignment
LEFT JOIN
  exchange_rates AS er
    ON er.currency_from = cs.currency_code
GROUP BY
  cs.id_assignment
