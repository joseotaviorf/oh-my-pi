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
    ba_categoria_do_gasto_v5_forrent_erro_5a AS ba_error_expense_category,
    ba_categoria_do_gasto_v5_forrent_nao_erro_5a AS ba_not_error_expense_category,
    ba_categoria_de_gasto_for_rent_motivacao_de_solicitacao_nao_erro_5a AS ba_not_error_expense_category_motivation_for_rent,
    CAST(ba_qual_o_valor_total_do_bandaid AS DOUBLE) AS ba_bandaid_value,
    CAST(ba_qual_e_o_valor_do_bandaid_forrental_aux AS DOUBLE) AS ba_bandaid_value_for_rent_aux,
    CAST(ba_valor_band_aid_for_rent AS DOUBLE) AS ba_bandaid_value_for_rent,
    TO_TIMESTAMP(created, 'd/M/yyyy H:mm:SS') AS ts_created,
    ts_load
FROM
    datalake_gsheets_raw.base_bandaids