SELECT
    id_creditor,
    id_customer,
    id_product,
    id_contract,
    id_indicator,
    indicator_content,
    content_description,
    MAKE_DATE(year, month, day) AS dt_snapshot,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_recupera_raw.indicator_contracts
QUALIFY row_number() OVER(PARTITION BY id_creditor, id_customer, id_product, id_contract, id_indicator, indicator_content, content_description ORDER BY ts_load DESC) = 1
