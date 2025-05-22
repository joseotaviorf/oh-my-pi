SELECT
    id_operador_cyber AS id_operator_cyber,
    id_operador_assessoria AS id_operator,
    nome AS name,
    email,
    cargo AS position,
    nome_lideranca AS leadership_name,
    tipo_pa AS pa_type,
    data_admissao AS dt_admission,
    data_desligamento AS dt_termination,
    NOW() AS ts_load
FROM datalake_meetcall_raw.dadosoperadores
