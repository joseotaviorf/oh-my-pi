-- Left half of vendor_natural_key is TENANT id_pessoa_pes; right half is id_contrato_con.
-- Query used TENANT.payload.id_sacado_sac; expose it from the row or the parent tenant.
WITH delinquency_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS vendor_natural_key,
        split(lake_mirror.vendor_natural_key, '\\\\|')[0] AS id_pessoa_pes,
        split(lake_mirror.vendor_natural_key, '\\\\|')[1] AS id_contrato_con,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_recebimento_recb') AS id_recebimento_recb,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_lancamento_imod') AS id_lancamento_imod,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_sacado_sac') AS id_sacado_sac_row,
        TO_DATE(get_json_object(CAST(lake_mirror.payload AS STRING), '$.dt_vencimento_recb')) AS dt_vencimento_recb,
        lake_mirror.synced_at AS ts_synced
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'DELINQUENCY'
)
SELECT
    delinquency_row.id,
    delinquency_row.vendor_natural_key,
    delinquency_row.id_pessoa_pes,
    delinquency_row.id_contrato_con,
    delinquency_row.id_recebimento_recb,
    delinquency_row.id_lancamento_imod,
    COALESCE(delinquency_row.id_sacado_sac_row, locatario.id_sacado_sac) AS id_sacado_sac,
    contrato.codigo_contrato,
    delinquency_row.dt_vencimento_recb,
    delinquency_row.ts_synced
FROM
    delinquency_row AS delinquency_row
LEFT JOIN
    datalake_benvi_manager_clean.benvi_superlogica_locatario AS locatario
        ON delinquency_row.id_pessoa_pes = locatario.id_pessoa_pes
LEFT JOIN
    datalake_benvi_manager_clean.benvi_superlogica_contrato AS contrato
        ON delinquency_row.id_contrato_con = contrato.id_contrato_con
