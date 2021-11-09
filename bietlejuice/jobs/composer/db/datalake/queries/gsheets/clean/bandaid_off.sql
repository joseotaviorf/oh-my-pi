SELECT
    CAST(NULLIF(contrato,'') AS INT) AS id_contract,
    NULLIF(key,'') AS id_issue,
    NULLIF(issue_type,'') AS issue_type,
    NULLIF(summary,'') AS summary,
    NULLIF(reporter,'') AS reporter,
    NULLIF(status,'') AS status,
    NULLIF(ba_departamento,'') AS ba_department,
    CAST(NULLIF(ba_valor_total,'') AS FLOAT) AS ba_total_value,
    NULLIF(ba_faixa_de_valor,'') AS ba_value_range,
    NULLIF(ba_categoria_do_gasto,'') AS ba_expense_category,
    NULLIF(ba_cliente_beneficiado,'') AS ba_client,
    TO_TIMESTAMP(NULLIF(created,''),'MM/dd/yyyy HH:mm:ss') AS ts_created
FROM
    datalake_gsheets_raw.jira_extraction_ba_sf
