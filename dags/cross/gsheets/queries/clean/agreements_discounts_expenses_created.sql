SELECT
    CAST(NULLIF(solicitacao,'') AS INT) AS id_request,
    CAST(NULLIF(contrato,'') AS INT) AS id_contract,
    CAST(NULLIF(imovel,'') AS INT) AS id_house,
    NULLIF(despesa,'') AS expense_name,
    NULLIF(de,'') AS from_account,
    NULLIF(para,'') AS to_account,
    NULLIF(tag,'') AS tag,
    CAST(NULLIF(valor,'') AS FLOAT) AS value,
    NULLIF(competencia,'') AS accrual_year_month,
    CAST(NULLIF(parcelas,'') AS INT) AS installments,
    NULLIF(status_fatura,'') AS invoice_status,
    CAST(NULLIF(tempo_decorrido,'') AS INT) AS elapsed_time,
    CAST(NULLIF(linha,'') AS INT) AS line,
    BOOLEAN(NULLIF(boleto_update,'')) AS has_invoice_update,
    BOOLEAN(NULLIF(fatura_fechada,'')) AS is_closed_invoice,
    CASE 
        WHEN timestamp IS NOT NULL AND timestamp <> '-' THEN TIMESTAMP(timestamp)
        ELSE NULL
    END AS ts_request
FROM
    datalake_gsheets_raw.entry_agreements_discounts_expenses