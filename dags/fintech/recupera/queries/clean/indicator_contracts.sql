WITH
history_check AS (
    SELECT
        *,
        LAG(indicator_content, 1) OVER (
            PARTITION BY id_creditor, id_customer, id_product, id_contract, id_indicator
            ORDER BY ts_load
        ) AS previous_value
    FROM
        datalake_recupera_raw.indicator_contracts
)
SELECT
    id_creditor,
    id_customer,
    id_product,
    id_contract,
    id_indicator,
    indicator_content,
    content_description,
    MAKE_DATE(year, month, day) AS dt_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    history_check
WHERE
    previous_value IS NULL
    OR indicator_content <> previous_value
