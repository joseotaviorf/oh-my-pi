SELECT
    key,
    issue_type,
    status,
    summary,
    ba_tipo_de_bandaid AS ba_bandaid_type,
    ba_codigo_do_contrato AS ba_contract,
    sf_codigo_do_contrato AS sf_contract,
    ba_departamento AS ba_department,
    ba_forrent_departamento AS ba_department_for_rent,
    ba_categoria_do_gasto_forrent AS ba_expense_category_for_rent,
    sf_categoria_do_gasto AS sf_expense_category,
    ba_etapa_da_jornada AS ba_stage_journey,
    ba_em_qual_etapa_da_jornada_ocorreu_o_erro_forrent AS ba_error_journey_step_for_rent,
    ba_em_qual_etapa_da_jornada_ocorreu_o_erro AS ba_error_journey_step,
    CAST(ba_qual_o_valor_total_do_bandaid AS DOUBLE) AS ba_bandaid_value,
    TO_TIMESTAMP(created, 'd/M/yyyy H:mm:SS') AS ts_created,
    ts_load
FROM
    datalake_gsheets_raw.base_bandaids
