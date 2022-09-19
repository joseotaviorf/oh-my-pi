SELECT
    CAST(contrato AS BIGINT) AS id_contract,
    despesa AS expense_description,
    CAST(valor AS DOUBLE) AS expense_value,
    CAST(valor_original AS DOUBLE) AS original_value,
    item,
    de AS payer,
    para AS payee,
    despesa_original AS original_expense_reason,
    cobranca AS collection_mode,
    versao AS contract_version,
    status,
    NULLIF(tipo_excecao, '') AS exception_type,
    CAST(NULLIF(tempo_decorrido, '') AS BIGINT) AS spent_time,
    BOOLEAN(condominio_ajustado) AS is_condo_adjusted,
    BOOLEAN(nova_garantia) AS is_new_guarantee,
    BOOLEAN(excecao) AS is_exception,
    TO_DATE(vigencia) AS dt_start,
    TO_DATE(rescisao, 'yyyyMMdd') AS dt_termination,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    ts_load
FROM
    datalake_gsheets_raw.offboarding_payments_expenses
