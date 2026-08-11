SELECT
    TXCASENO AS id_case,
    TXCON AS id_contract,
    TXADDDT AS ts_added,
    year,
    month,
    day,
    NOW() AS ts_load
FROM datalake_cyber_legal_raw.text_content
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
