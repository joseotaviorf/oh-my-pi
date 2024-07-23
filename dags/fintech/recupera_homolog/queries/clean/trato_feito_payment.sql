SELECT
    id_receipt,
    installment_code,
    CASE
        WHEN payment_traffic_flag = "E" THEN "Enviar ao Trato-Feito"
        WHEN payment_traffic_flag = "X" THEN "Flag temporário para tratar o registro"
        WHEN payment_traffic_flag = "S" THEN "Enviado ao Trato-Feito"
        ELSE payment_traffic_flag
    END AS payment_traffic_flag,
    error_description_trato_feito,
    CAST(internal_code AS INT) AS internal_code,
    CAST(trato_feito_payment_send AS INT) AS trato_feito_payment_send,
    TIMESTAMP(ts_current_registration) AS ts_current_registration,
    TIMESTAMP(ts_trato_feito_payment) AS ts_trato_feito_payment,
    ts_load,
    year,
    month,
    day
FROM
    datalake_recupera_homolog_raw.trato_feito_payment
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
