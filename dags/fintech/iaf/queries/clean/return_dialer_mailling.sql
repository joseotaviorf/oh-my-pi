SELECT
    id,
    idempresa AS id_company,
    idmailling AS id_mailling,
    fila_id AS id_line,
    status_ret_id AS id_status_return,
    id_ret,
    id_ext,
    processo AS process,
    status,
    fone AS phone,
    status_ret,
    status_ret_externo AS external_status_return,
    hora_cad AS hr_cad,
    data_cad AS dt_cad
FROM
    datalake_iaf_raw.vi_319_tb_mailling_discador_retorno
