WITH after_12_months_revenue_by_guarantee_bill_items AS (
  WITH cte_split_bill_item AS (
    SELECT
      id,
      UPPER(REVERSE(SPLIT(bill_item, '/')) [0]) AS bill_item,
      id_invoice
    FROM
      datalake_retsuko.entry
  ),
  analytical_db_manual_revenue_bill_item AS (
    SELECT
      rcc.id_external AS id_contract,
      rci.id_external AS id_invoice,
      rci.purpose,
      rci.status AS payment_status,
      bi.bill_item AS bill_item,
      rce.description AS bill_item_description,
      rca.type AS from_account_type,
      rcab.type AS to_account_type,
      CASE
        WHEN (
          rca.type = 'contract'
          AND rcab.type <> 'contract'
        ) THEN (-1.0) * rce.amount
        ELSE 1.0 * rce.amount
      END AS value_sign_bill_item,
      rci.due_amount,
      rce.accrual_year_month AS accrual_year_month,
      rci.accrual_year_month AS accrual_year_month_invoice,
      CAST(rci.ts_created AS DATE) AS dt_created,
      CAST(rci.ts_sent AS DATE) AS dt_sent,
      CAST(rci.ts_due AS DATE) AS dt_due,
      CAST(rci.ts_paid AS DATE) AS dt_paid,
      CAST(rci.ts_canceled AS DATE) AS dt_canceled
    FROM
      datalake_retsuko.invoice AS rci
      LEFT JOIN cte_split_bill_item AS bi ON bi.id_invoice = rci.id
      LEFT JOIN datalake_retsuko.entry AS rce ON bi.id = rce.id
      LEFT JOIN datalake_retsuko_clean.account AS rca ON rca.id = rce.id_from_account
      LEFT JOIN datalake_retsuko_clean.account AS rcab ON rcab.id = rce.id_to_account
      LEFT JOIN datalake_retsuko_clean.contract AS rcc ON rcc.id = rci.id_contract
    WHERE
      bi.bill_item IN (UPPER('rental-guarantee-fee'), UPPER("pro-guarantor-5A-installment"))
      AND rca.type = 'tenant'
      AND rcab.type = 'contract'
      AND rci.due_amount <= 0
  ),
  base_agg AS (
    SELECT
      id_contract,
      accrual_year_month AS accrual_year_month_running,
      SUM(value_sign_bill_item) AS raw_payment_amount
    FROM
      analytical_db_manual_revenue_bill_item
    GROUP BY 1,2
  )
  SELECT
    *,
    'MONTHLY-PAYMENT' AS origin_fact
  FROM
    base_agg
),
deposit_view AS (
  WITH BASE_CHARGES AS (
    SELECT
      contract.id AS id_contract,
      guarantee.guarantee_type,
      guarantee.id AS guarantee_id,
      contract.id_proposal,
      dpdc.status AS contract_status,
      dpdc.dt_started AS dt_start,
      dpdc.dt_termination AS dt_annulment,
      COALESCE(
        date_trunc('month', dpdc.dt_started),
        date_trunc('month', dpdc.dt_entered)
      ) AS dt_started_imported,
      COALESCE(
        date_trunc('month', dpdc.dt_termination),
        date_trunc('month', current_date)
      ) AS dt_ended_imported,
      guarantee.final_value AS guarantee_total_value,
      charge.id AS id_charge,
      charge.installments,
      charge.charge_type,
      guarantee.ts_paid AS ts_first_payment_paid,
      charge.charge_status,
      charge.ts_updated AS ts_charge_payment,
      charge.ts_created AS ts_charge_created
    FROM
      datalake_rental_guarantee.guarantee guarantee
      LEFT JOIN datalake_ebdb_contract.contract contract ON guarantee.id_contract_ebdb = contract.id
      LEFT JOIN datalake_rental_guarantee.charge charge ON charge.id_guarantee = guarantee.id
      LEFT JOIN datalake_ebdb_contract.contract AS dpdc ON dpdc.id = contract.id
    WHERE
      contract.status IN ('Ativo', 'Finalizado')
      AND guarantee.guarantee_type = 'DEPOSIT'
      AND dpdc.dt_started <= cast('2100-01-01' AS date)
      AND dpdc.dt_started >= cast('2015-01-01' AS date)
      AND charge.charge_status <> 'CANCELED'
      AND charge.charge_status <> 'FAILED'
  ),
  charges_updated_database AS (
    SELECT
      *,
      ROW_NUMBER() OVER(
        PARTITION BY id_contract
        ORDER BY
          ts_charge_created ASC
      ) AS rowNumber
    FROM
      BASE_CHARGES
    WHERE
      TRUE
      AND ts_charge_created <= dt_start + interval '10' day
  ),
  base_unica_contrato AS (
    SELECT
      id_contract,
      guarantee_id,
      id_charge,
      id_proposal,
      guarantee_type,
      contract_status,
      dt_start AS dt_start_contract,
      CAST(
        CAST(
          YEAR(add_months(ts_charge_created, 0)) AS STRING
        ) || LPAD(
          CAST(
            MONTH(add_months(ts_charge_created, 0)) AS STRING
          ),
          2,
          '0'
        ) AS INTEGER
      ) AS accrual_year_month_running,
      dt_annulment AS dt_annulment_contract,
      dt_started_imported,
      dt_ended_imported,
      charge_type,
      charge_status,
      installments,
      guarantee_total_value,
      ts_first_payment_paid,
      ts_charge_payment,
      ts_charge_created
    FROM
      charges_updated_database
    WHERE
      rowNumber = 1
  )
  SELECT
    id_contract,
    accrual_year_month_running,
    guarantee_total_value AS raw_payment_amount,
    'DOWN PAYMENT' AS origin_fact
  FROM
    base_unica_contrato
),
  guarantee_aud AS (
    WITH aud AS (
      SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY id_contract_ebdb ORDER BY rev ASC) AS rowNumber
      FROM
        datalake_rental_guarantee_clean.guarantee_aud
    )
    SELECT
      id_contract_ebdb,
      final_value/100 AS final_value
    FROM
      aud
    WHERE
      id_contract_ebdb IS NOT NULL
),
down_payment_guarantees_no_deposit AS (
  WITH BASE_CHARGES AS (
    SELECT
      contract.id AS id_contract,
      guarantee.guarantee_type,
      guarantee.id AS guarantee_id,
      contract.id_proposal,
      dpdc.status AS contract_status,
      dpdc.dt_started AS dt_start,
      dpdc.dt_termination AS dt_annulment,
      COALESCE(
        date_trunc('month', dpdc.dt_started),
        date_trunc('month', dpdc.dt_entered)
      ) AS dt_started_imported,
      COALESCE(
        date_trunc('month', dpdc.dt_termination),
        date_trunc('month', current_date)
      ) AS dt_ended_imported,
      COALESCE(
        aud.final_value,
        guarantee.final_value
      ) AS guarantee_total_value,
      COALESCE(
        aud.final_value/12,
        guarantee.final_value/12
        )  AS valor_mensal_garantia,
      charge.id AS id_charge,
      charge.installments AS installments,
      charge.charge_type,
      guarantee.ts_paid AS ts_first_payment_paid,
      charge.charge_status,
      charge.ts_updated AS ts_charge_payment,
      charge.ts_created AS ts_charge_created
    FROM
      datalake_rental_guarantee.guarantee guarantee
      LEFT JOIN datalake_ebdb_contract.contract contract on guarantee.id_contract_ebdb = contract.id
      LEFT JOIN datalake_rental_guarantee.charge charge on charge.id_guarantee = guarantee.id
      LEFT JOIN datalake_ebdb_contract.contract AS dpdc on dpdc.id = contract.id
      LEFT JOIN guarantee_aud AS aud ON aud.id_contract_ebdb = guarantee.id_contract_ebdb
    WHERE
      contract.status IN ('Ativo', 'Finalizado')
      AND guarantee.guarantee_type <> 'DEPOSIT'
      AND dpdc.dt_started <= cast('2100-01-01' AS date)
      AND dpdc.dt_started >= cast('2015-01-01' AS date)
      AND charge.charge_status <> 'CANCELED'
      AND charge.charge_status <> 'FAILED'
  ),
  charges_updated_database AS (
    SELECT
      *,
      ROW_NUMBER() OVER(
        PARTITION BY id_contract
        ORDER BY
          ts_charge_payment ASC
      ) AS rowNumber
    FROM
      BASE_CHARGES
    WHERE
      TRUE
      and ts_charge_created <= dt_start + interval '10' day
  ),
  base_unica_contrato AS (
    SELECT
      id_contract,
      guarantee_id,
      id_charge,
      id_proposal,
      guarantee_type,
      contract_status,
      dt_start AS dt_start_contract,
      dt_annulment AS dt_annulment_contract,
      dt_started_imported,
      dt_ended_imported,
      charge_type,
      charge_status,
      installments,
      guarantee_total_value,
      valor_mensal_garantia,
      ts_first_payment_paid,
      ts_charge_payment
    FROM
      charges_updated_database
    WHERE
      rowNumber = 1
  ),
  base_ajuste_datas AS (
    SELECT
      distinct base_unica_contrato.*,
      CAST(
        CAST(YEAR(dd.month_start) AS STRING) || LPAD(CAST(MONTH(dd.month_start) AS STRING), 2, '0') AS INTEGER
      ) AS accrual_year_month_running
    FROM
      base_unica_contrato
      INNER JOIN dw_public.dim_date AS dd ON dd.date BETWEEN dt_started_imported
      AND dt_ended_imported
  ),
  cap_em_12_meses AS (
    SELECT
      *,
      ROW_NUMBER() OVER(
        PARTITION BY id_contract
        ORDER BY
          accrual_year_month_running asc
      ) AS monthly_order
    FROM
      base_ajuste_datas
  ),
  fix_last_month AS (
    SELECT
      *,
      COUNT(guarantee_id) OVER(PARTITION BY id_contract) AS max_number_months
    FROM
      cap_em_12_meses
    WHERE
      monthly_order <= 12
  )
  SELECT
    id_contract,
    accrual_year_month_running,
    valor_mensal_garantia AS raw_payment_amount,
    'DOWN_PAYMENT' AS origin_fact
  FROM
    fix_last_month
),
full_revenue AS (
  WITH stacked_revenue AS (
    SELECT
      *
    FROM
      after_12_months_revenue_by_guarantee_bill_items
    UNION ALL
    SELECT
      *
    FROM
      down_payment_guarantees_no_deposit
    UNION ALL
    SELECT
      *
    FROM
      deposit_view
  ),
  dimensions AS (
    SELECT
      DISTINCT contract.id AS id_contract,
      guarantee.guarantee_type,
      guarantee.id AS guarantee_id,
      contract.id_proposal,
      guarantee.ts_created
    FROM
      datalake_rental_guarantee.guarantee guarantee
      LEFT JOIN datalake_ebdb_contract.contract contract on guarantee.id_contract_ebdb = contract.id
      LEFT JOIN datalake_rental_guarantee.charge charge on charge.id_guarantee = guarantee.id
      LEFT JOIN datalake_ebdb_contract.contract AS dpdc on dpdc.id = contract.id
    WHERE
      contract.status IN ('Ativo', 'Finalizado')
      AND dpdc.dt_started <= cast('2100-01-01' AS date)
      AND dpdc.dt_started >= cast('2015-01-01' AS date)
      AND charge.charge_status <> 'CANCELED'
      AND charge.charge_status <> 'FAILED'
  )
  SELECT
    m.*,
    f.guarantee_type,
    f.id_proposal,
    f.guarantee_id,
    f.ts_created
  FROM
    stacked_revenue AS m
    LEFT JOIN dimensions AS f on f.id_contract = m.id_contract
),
full_revenue_remove_duplicates AS (
  WITH temp_table AS (
    SELECT
      *,
      ROW_NUMBER() OVER(
        PARTITION BY id_contract,
        accrual_year_month_running
        ORDER BY
          accrual_year_month_running asc
      ) AS number_payments
    FROM
      full_revenue
  )
  SELECT
    *
  FROM
    temp_table
  WHERE
    number_payments = 1
)
SELECT
  id_contract,
  guarantee_id as id_guarantee,
  id_proposal,
  accrual_year_month_running as accrual_year_month,
  number_payments,
  origin_fact,
  raw_payment_amount,
  CASE
    WHEN guarantee_type = 'INSURANCE' THEN raw_payment_amount * 0.825 / 1.0738
    WHEN guarantee_type = 'PRO_GUARANTOR'
    OR guarantee_type = 'STANDALONE' THEN raw_payment_amount
    WHEN guarantee_type = 'DEPOSIT'
    AND accrual_year_month_running <= 202211 THEN raw_payment_amount * 0.02
    WHEN guarantee_type = 'DEPOSIT'
    AND accrual_year_month_running > 202211 THEN raw_payment_amount * 0.03
  END AS revenue_qa,
  guarantee_type,
  ts_created as ts_guarantee_created
FROM
  full_revenue_remove_duplicates
