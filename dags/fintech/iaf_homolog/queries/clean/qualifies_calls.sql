SELECT
    id,
    idempresa AS id_company,
    idcredor AS id_creditor,
    iddevedor AS id_debtor,
    id_uuid,
    idocorrencia AS id_occurrence,
    processo AS process,
    operador AS operator,
    qualifica AS qualifies,
    fone AS phone,
    userfield AS user_field,
    ramal AS extension,
    disposition,
    positivo AS positive,
    userfield2 AS user_field_2,
    segundostotal AS total_seconds,
    hora_cad AS hr_cad,
    data_cad AS dt_cad
FROM
    datalake_iaf_raw.vi_319_tb_qualifica_chamadas
