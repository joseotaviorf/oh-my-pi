SELECT
    CAST(NULLIF(solicitacao,'') AS INT) AS id_request,
    CAST(NULLIF(contrato,'') AS INT) AS id_contract,
    CAST(NULLIF(imovel,'') AS INT) AS id_house,
    CAST(NULLIF(cpf,'') AS INT) AS id_user_cpf,
    NULLIF(tarefa,'') AS task,
    NULLIF(analista,'') AS analyst,
    NULLIF(origem,'') AS origin,
    NULLIF(despesa,'') AS expense,
    NULLIF(de,'') AS from_account,
    NULLIF(para,'') AS to_account,
    CAST(NULLIF(valor,'') AS FLOAT) AS value,
    CAST(NULLIF(multa,'') AS FLOAT) AS assessment,
    CAST(NULLIF(parcelas,'') AS INT) AS installments,
    NULLIF(ticket,'') AS ticket,
    NULLIF(resumo,'') AS summary,
    NULLIF(titular,'') AS holder,
    NULLIF(banco,'') AS bank,
    NULLIF(agencia,'') AS bank_branch_code,
    NULLIF(conta,'') AS account_number,
    NULLIF(tipo,'') AS type,
    NULLIF(mes_vencimento,'') AS month_due,
    CAST(NULLIF(linha,'') AS INT) AS line,
    NULLIF(observacao,'') AS note,
    NULLIF(time,'') AS time,
    BOOLEAN(NULLIF(get_net,'')) AS is_get_net,
    BOOLEAN(NULLIF(isentar_juros,'')) AS is_exempt_interest,
    DATE(NULLIF(vencimento,'')) AS dt_due,
    DATE(NULLIF(ref_mes,'')) AS dt_ref_month,
    CASE 
        WHEN cancelado IS NOT NULL AND cancelado <> '-' THEN TIMESTAMP(cancelado)
        ELSE NULL
    END AS ts_canceled,
    CASE 
        WHEN execucao IS NOT NULL AND execucao <> '-' THEN TIMESTAMP(execucao)
        ELSE NULL
    END AS ts_execution,
    CASE 
        WHEN timestamp IS NOT NULL AND timestamp <> '-' THEN TIMESTAMP(timestamp)
        ELSE NULL
    END AS ts_request
FROM
    datalake_gsheets_raw.extra_invoice