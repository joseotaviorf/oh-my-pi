WITH gs AS (
    SELECT
        qualifies,
        alo,
        cpc
    FROM
        datalake_gsheets_clean.quintocred_iaf_qualifies_calls
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY qualifies ORDER BY qualifies ASC) = 1
)

SELECT
    qc.id,
    qc.idempresa AS id_company,
    qc.idcredor AS id_creditor,
    qc.iddevedor AS id_debtor,
    qc.id_uuid,
    qc.idocorrencia AS id_occurrence,
    qc.processo AS process,
    qc.operador AS operator,
    qc.qualifica AS qualifies,
    qc.fone AS phone,
    qc.userfield AS user_field,
    qc.ramal AS extension,
    qc.disposition,
    qc.positivo AS positive,
    qc.userfield2 AS user_field_2,
    qc.segundostotal AS total_seconds,
    CAST(COALESCE(gs.alo, 0) AS INTEGER) AS alo,
    CAST(COALESCE(gs.cpc, 0) AS INTEGER) AS cpc,
    qc.hora_cad AS hr_cad,
    qc.data_cad AS dt_cad
FROM
    datalake_iaf_raw.vi_319_tb_qualifica_chamadas qc
LEFT JOIN 
    gs
    ON qc.qualifica = gs.qualifies
