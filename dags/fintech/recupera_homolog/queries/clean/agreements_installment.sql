SELECT
    id_installment,
    id_creditor,
    id_customer,
    id_product,
    id_contract,
    id_installment_agreement,
    installment_number,
    DATE(dt_due) AS dt_due,
    ts_load,
    year,
    month,
    day
FROM
    datalake_recupera_homolog_raw.agreements_installment
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
