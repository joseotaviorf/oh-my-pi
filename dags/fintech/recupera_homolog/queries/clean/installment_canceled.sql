SELECT
    id_installment,
    id_operator,
    CASE
        WHEN has_commissioning_transfer = "S" THEN True
        ELSE False
    END AS has_commissioning_transfer,
    broken_agreements,
    TIMESTAMP(ts_canceled_installment) AS ts_canceled_installment,
    DATE(dt_transfer) AS dt_transfer,
    ts_load,
    year,
    month,
    day
FROM
    datalake_recupera_homolog_raw.installment_canceled
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
