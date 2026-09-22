-- Nested CONTRACT.payload.inquilinos. Not a Superlogica HTTP extractor.
-- One row per tenant on a contract, the shape of the RAW contratos_inquilinos tab.
-- id_imovel_imo is carried down from the parent contract payload, matching the way the
-- extraction script merges parent keys into every nested row.
WITH contract_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS id_contrato_con,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_imovel_imo') AS id_imovel_imo,
        lake_mirror.synced_at AS ts_synced,
        FROM_JSON(
            get_json_object(CAST(lake_mirror.payload AS STRING), '$.inquilinos'),
            'array<map<string,string>>'
        ) AS inquilinos
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'CONTRACT'
)
SELECT
    contract_row.id,
    contract_row.id_contrato_con,
    contract_row.id_imovel_imo,
    CAST(item_row.nr_item AS INT) + 1 AS nr_item,
    item_row.item_map['id_sacado_sac'] AS id_sacado_sac,
    item_row.item_map['st_fantasia_pes'] AS st_fantasia_pes,
    item_row.item_map['st_endereco_pes'] AS st_endereco_pes,
    item_row.item_map['st_numero_pes'] AS st_numero_pes,
    item_row.item_map['st_complemento_pes'] AS st_complemento_pes,
    item_row.item_map['st_cidade_pes'] AS st_cidade_pes,
    item_row.item_map['st_estado_pes'] AS st_estado_pes,
    item_row.item_map['st_cep_pes'] AS st_cep_pes,
    item_row.item_map['st_bairro_pes'] AS st_bairro_pes,
    item_row.item_map['st_cnpj_pes'] AS st_cnpj_pes,
    item_row.item_map['st_orgao_pes'] AS st_orgao_pes,
    item_row.item_map['dt_expedicaorg_pes'] AS dt_expedicaorg_pes,
    item_row.item_map['st_rg_pes'] AS st_rg_pes,
    item_row.item_map['st_nacionalidade_pes'] AS st_nacionalidade_pes,
    item_row.item_map['st_naturalidade_pes'] AS st_naturalidade_pes,
    item_row.item_map['st_estadocivil_pes'] AS st_estadocivil_pes,
    item_row.item_map['st_profissao_pes'] AS st_profissao_pes,
    item_row.item_map['st_email_pes'] AS st_email_pes,
    item_row.item_map['st_telefone_pes'] AS st_telefone_pes,
    item_row.item_map['st_celular_pes'] AS st_celular_pes,
    item_row.item_map['st_nomeresp_pes'] AS st_nomeresp_pes,
    item_row.item_map['dt_nascimento_pes'] AS dt_nascimento_pes,
    item_row.item_map['st_sexo_pes'] AS st_sexo_pes,
    item_row.item_map['st_nome_coj'] AS st_nome_coj,
    item_row.item_map['st_cpf_coj'] AS st_cpf_coj,
    item_row.item_map['fl_statusconvitecartao_pes'] AS fl_statusconvitecartao_pes,
    item_row.item_map['st_razaoempresa_pes'] AS st_razaoempresa_pes,
    item_row.item_map['id_pessoa_pes'] AS id_pessoa_pes,
    item_row.item_map['fl_principal_inq'] AS fl_principal_inq,
    item_row.item_map['nm_fracao_inq'] AS nm_fracao_inq,
    item_row.item_map['st_nomeinquilino'] AS st_nomeinquilino,
    item_row.item_map['st_nomeinquilino_formatado'] AS st_nomeinquilino_formatado,
    TO_JSON(item_row.item_map) AS item_payload,
    contract_row.ts_synced
FROM
    contract_row AS contract_row
LATERAL VIEW POSEXPLODE(contract_row.inquilinos) item_row AS nr_item, item_map
