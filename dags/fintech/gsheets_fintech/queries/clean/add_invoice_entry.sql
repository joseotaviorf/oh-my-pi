SELECT
    CAST(to_date(execucao, 'M/d/yyyy') AS DATE) AS execution_timestamp,
    CAST(ref_mes AS DATE) AS reference_month_date,
    CAST(ref_inicio AS DATE) AS reference_start_date,
    CAST(ref_final AS DATE) AS reference_end_date,
    CAST(to_date(data_de_execucao_do_dispatcher, 'M/d/yyyy') AS DATE) AS dispatcher_execution_date,
    CAST(solicitacao AS INT) AS request_id,
    CAST(contrato AS INT) AS contract_id,
    CAST(imovel AS INT) AS property_id,
    CAST(ticket AS INT) AS ticket_id,
    CAST(id_da_botcity AS STRING) AS botcity_execution_id,
    CAST(origem AS STRING) AS origin_source,
    CAST(analista AS STRING) AS analyst_email,
    CAST(tipodesolicitacao AS STRING) AS request_type,
    CAST(quempaga AS STRING) AS payer_type,
    CAST(quemrecebe AS STRING) AS receiver_type,
    CAST(despesa AS STRING) AS expense_type,
    CAST(valor AS DECIMAL(10, 2)) AS expense_value,
    CAST(parcelas AS INT) AS installment_count
FROM
    datalake_gsheets_raw.add_invoice_entry
