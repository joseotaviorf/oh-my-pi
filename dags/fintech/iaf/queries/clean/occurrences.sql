SELECT
    idempresa AS id_company,
    idocorrencia AS id_occurrence,
    idcredor AS id_creditor,
    iddevedor AS id_debtor,
    idrecebimento AS id_receipt,
    processo AS process,
    operador AS operator,
    anotaint AS int_note,
    anotaext AS ext_note,
    descstatus AS desc_status,
    segundostotal AS total_seconds,
    operadortipo AS operator_type,
    codstatus AS code_status,
    origem AS origin,
    horainicial AS hr_begin,
    horafinal AS hr_end,
    tempototal AS total_time,
    datacad AS dt_cad
FROM
    datalake_iaf_raw.vi_319_tb_ocorrencias
