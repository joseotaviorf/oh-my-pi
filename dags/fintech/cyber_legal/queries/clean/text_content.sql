SELECT
    TXCASENO AS id_case,
    TXCON AS id_contract,
    TXADDDT AS ts_added,
    NOW() AS ts_load
FROM datalake_cyber_legal_raw.text_content
