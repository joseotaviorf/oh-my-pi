WITH gs AS (
    SELECT 
        desc_status,	
        tab,
        effort,	
        massive,	
        channel
    FROM 
        datalake_gsheets_clean.quintocred_iaf_occurrences
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY desc_status ORDER BY desc_status ASC) = 1
)

SELECT
    oc.idempresa AS id_company,
    oc.idocorrencia AS id_occurrence,
    oc.idcredor AS id_creditor,
    oc.iddevedor AS id_debtor,
    oc.idrecebimento AS id_receipt,
    oc.processo AS process,
    oc.operador AS operator,
    oc.anotaint AS int_note,
    oc.anotaext AS ext_note,
    oc.descstatus AS desc_status,
    oc.segundostotal AS total_seconds,
    oc.operadortipo AS operator_type,
    oc.codstatus AS code_status,
    oc.origem AS origin,
    oc.horainicial AS hr_begin,
    oc.horafinal AS hr_end,
    oc.tempototal AS total_time,
    gs.tab,
    CAST(COALESCE(gs.effort, 0) AS INTEGER) AS effort,
    CAST(COALESCE(gs.massive, 0) AS INTEGER) AS massive,
    gs.channel,
    oc.datacad AS dt_cad
FROM
    datalake_iaf_raw.vi_319_tb_ocorrencias oc
LEFT JOIN 
    gs
    ON oc.descstatus = gs.desc_status
