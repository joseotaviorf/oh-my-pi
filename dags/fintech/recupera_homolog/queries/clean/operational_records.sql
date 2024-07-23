SELECT
    id_creditor,
    id_customer,
    id_distribution,
    id_site,
    id_operator,
    CASE
        WHEN balance_update_routine_indicator = "1" THEN "Aguardando processamento"
        WHEN balance_update_routine_indicator = "9" THEN "Já processado"
        WHEN balance_update_routine_indicator = "2" THEN "Registro de trânsito (uso interno Recupera)"
        ELSE balance_update_routine_indicator
    END AS balance_update_routine_indicator,
    collesction_customer_situation,
    origin,
    customer_oldest_debt_maturity,
    CASE
        WHEN is_next_customer = "S" THEN True
        ELSE False
    END AS is_next_customer,
    last_customer_history_code,
    advisory_code,
    product_code,
    distributor_code,
    operator_code_last_contact,
    CAST(distribution_phase AS INT) AS distribution_phase,
    CAST(calls_same_occurence AS INT) AS calls_same_occurence,
    CAST(latest_installment_number AS INT) AS latest_installment_number,
    CAST(overdue_customer_debt_balance AS FLOAT) AS  overdue_customer_debt_balance,
    CAST(installment_amount AS FLOAT) AS installment_amount,
    DATE(dt_reference) AS dt_reference,
    DATE(dt_debt_freezing) AS dt_debt_freezing,
    DATE(dt_deadline) AS dt_deadline,
    DATE(dt_enrollment_receipt) AS dt_enrollment_receipt,
    DATE(dt_customer_insertion) AS dt_customer_insertion,
    TIMESTAMP(ts_operator_code_update) AS ts_operator_code_update,
    TIMESTAMP(ts_last_update) AS ts_last_update,
    TIMESTAMP(ts_customer_status_last_update) AS ts_customer_status_last_update,
    ts_load,
    year,
    month,
    day
FROM
    datalake_recupera_homolog_raw.operational_records
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
