-- PII: st_nome_sac, st_cgc_sac, st_email_sac, and address fields.
-- PK is id_acordo_aco | id_recebimento_recb. id_acordo_aco groups parcels.
-- Join AGREEMENT.id_recebimento_recb to cobranca and id_sacado_sac to locatario.id_sacado_sac.
WITH agreement_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS vendor_natural_key,
        split(lake_mirror.vendor_natural_key, '\\\\|')[0] AS id_acordo_aco,
        COALESCE(
            split(lake_mirror.vendor_natural_key, '\\\\|')[1],
            get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_recebimento_recb')
        ) AS id_recebimento_recb,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_sacado_sac') AS id_sacado_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_nome_sac') AS st_nome_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_cgc_sac') AS st_cgc_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_email_sac') AS st_email_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_endereco_sac') AS st_endereco_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_numero_sac') AS st_numero_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_complemento_sac') AS st_complemento_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_bairro_sac') AS st_bairro_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_cidade_sac') AS st_cidade_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_estado_sac') AS st_estado_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_cep_sac') AS st_cep_sac,
        TO_DATE(get_json_object(CAST(lake_mirror.payload AS STRING), '$.dt_vencimento_recb')) AS dt_vencimento_recb,
        lake_mirror.synced_at AS ts_synced
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'AGREEMENT'
),
tenant_by_sacado AS (
    SELECT
        locatario.id_pessoa_pes,
        locatario.id_sacado_sac,
        ROW_NUMBER() OVER (
            PARTITION BY locatario.id_sacado_sac
            ORDER BY locatario.id
        ) AS rn
    FROM
        datalake_benvi_manager_clean.benvi_superlogica_locatario AS locatario
    WHERE
        locatario.id_sacado_sac IS NOT NULL
)
SELECT
    agreement_row.id,
    agreement_row.vendor_natural_key,
    agreement_row.id_acordo_aco,
    agreement_row.id_recebimento_recb,
    agreement_row.id_sacado_sac,
    tenant_by_sacado.id_pessoa_pes,
    cobranca.id_contrato_con,
    agreement_row.st_nome_sac,
    agreement_row.st_cgc_sac,
    agreement_row.st_email_sac,
    agreement_row.st_endereco_sac,
    agreement_row.st_numero_sac,
    agreement_row.st_complemento_sac,
    agreement_row.st_bairro_sac,
    agreement_row.st_cidade_sac,
    agreement_row.st_estado_sac,
    agreement_row.st_cep_sac,
    agreement_row.dt_vencimento_recb,
    agreement_row.ts_synced
FROM
    agreement_row AS agreement_row
LEFT JOIN
    tenant_by_sacado AS tenant_by_sacado
        ON agreement_row.id_sacado_sac = tenant_by_sacado.id_sacado_sac
        AND tenant_by_sacado.rn = 1
LEFT JOIN
    datalake_benvi_manager_clean.benvi_superlogica_cobranca AS cobranca
        ON agreement_row.id_recebimento_recb = cobranca.id_recebimento_recb
