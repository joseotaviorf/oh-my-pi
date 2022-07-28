SELECT
    CAST(NULLIF(solicitacao,'') AS INT) AS id_request,
    CAST(NULLIF(contrato,'') AS INT) AS id_contract,
    CAST(NULLIF(imovel,'') AS INT) AS id_house,
    NULLIF(tarefa,'') AS task,
    NULLIF(analista,'') AS analyst,
    NULLIF(origem,'') AS origin,
    NULLIF(despesa,'') AS expenses,
    NULLIF(de,'') AS from_account,
    NULLIF(para,'') AS to_account,
    CAST(NULLIF(valor,'') AS FLOAT) AS value,
    NULLIF(parcelas,'') AS installment_type,
    NULLIF(ticket,'') AS ticket,
    NULLIF(resumo,'') AS summary,
    NULLIF(qtde_meses,'') AS num_of_months,
    CAST(NULLIF(parcelamento,'') AS INT) AS num_of_installments,
    NULLIF(obs,'') AS note,
    CAST(NULLIF(task_row,'') AS INT) AS task_row,
    NULLIF(exp_num,'') AS exp_num,
    CAST(NULLIF(sla_corrido,'') AS INT) AS sla,
    NULLIF(split_queue,'') AS split_queue,
    NULLIF(bot_mega,'') AS bot_mega,
    DATE(NULLIF(vencimento,'')) AS dt_due,
    DATE(NULLIF(ref_mes,'')) AS dt_ref_month,
    DATE(NULLIF(ref_inicial,'')) AS dt_initial_ref,
    DATE(NULLIF(ref_final,'')) AS dt_final_ref,
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
    datalake_gsheets_raw.entry_agreements_discounts_forms