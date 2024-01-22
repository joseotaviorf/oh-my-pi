SELECT
    key,
    issue_type,
    status,
    summary,
    ba_tipo_de_bandaid AS ba_bandaid_type,
    ba_codigo_do_contrato AS ba_contract,
    ba_departamento AS ba_department,
    ba_forrent_departamento AS ba_department_for_rent,
    ba_categoria_do_gasto_forrent AS ba_expense_category_for_rent,
    ba_categoria_do_gasto AS ba_expense_category,
    ba_categoria_do_gasto_relatorio AS ba_expense_category_relatory,
    ba_causa_do_bandaid AS ba_bandaid_cause,
    ba_causa_do_bandaid_relatorio AS ba_bandaid_cause_relatory,
    ba_causa_raiz_do_bandaid_forrent AS ba_bandaid_root_cause_for_rent,
    ba_causa_raiz_do_bandaid AS ba_bandaid_root_cause,
    CAST(ba_qual_o_valor_total_do_bandaid AS DOUBLE) AS ba_bandaid_value,
    CAST(ba_valor_band_aid_for_rent AS DOUBLE) AS ba_bandaid_value_for_rent,
    TO_TIMESTAMP(created, 'd/M/yyyy H:mm:SS') AS ts_created,
    ts_load
FROM
    datalake_gsheets_raw.base_bandaids