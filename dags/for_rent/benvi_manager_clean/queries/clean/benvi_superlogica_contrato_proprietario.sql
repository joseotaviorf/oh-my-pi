-- Nested CONTRACT.payload.proprietarios_beneficiarios. Not a Superlogica HTTP extractor.
-- One row per beneficiary owner on a contract, the shape of the RAW contratos_proprietarios
-- tab, including the payout instruction the vendor attaches to each owner.
-- id_imovel_imo is carried down from the parent contract payload.
WITH contract_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS id_contrato_con,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_imovel_imo') AS id_imovel_imo,
        lake_mirror.synced_at AS ts_synced,
        FROM_JSON(
            get_json_object(CAST(lake_mirror.payload AS STRING), '$.proprietarios_beneficiarios'),
            'array<map<string,string>>'
        ) AS proprietarios_beneficiarios
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
    item_row.item_map['st_fantasia_pes'] AS st_fantasia_pes,
    item_row.item_map['st_nome_pes'] AS st_nome_pes,
    item_row.item_map['st_cnpj_pes'] AS st_cnpj_pes,
    item_row.item_map['st_orgao_pes'] AS st_orgao_pes,
    item_row.item_map['dt_expedicaorg_pes'] AS dt_expedicaorg_pes,
    item_row.item_map['st_rg_pes'] AS st_rg_pes,
    item_row.item_map['st_nacionalidade_pes'] AS st_nacionalidade_pes,
    item_row.item_map['st_naturalidade_pes'] AS st_naturalidade_pes,
    item_row.item_map['st_estadocivil_pes'] AS st_estadocivil_pes,
    item_row.item_map['st_profissao_pes'] AS st_profissao_pes,
    item_row.item_map['st_endereco_pes'] AS st_endereco_pes,
    item_row.item_map['dt_nascimento_pes'] AS dt_nascimento_pes,
    item_row.item_map['st_numero_pes'] AS st_numero_pes,
    item_row.item_map['st_bairro_pes'] AS st_bairro_pes,
    item_row.item_map['st_cidade_pes'] AS st_cidade_pes,
    item_row.item_map['st_estado_pes'] AS st_estado_pes,
    item_row.item_map['st_nomeresp_pes'] AS st_nomeresp_pes,
    item_row.item_map['st_email_pes'] AS st_email_pes,
    item_row.item_map['st_celular_pes'] AS st_celular_pes,
    item_row.item_map['st_telefone_pes'] AS st_telefone_pes,
    item_row.item_map['fl_descontosimplificadoir_pes'] AS fl_descontosimplificadoir_pes,
    item_row.item_map['id_formarecebimento_frp'] AS id_formarecebimento_frp,
    item_row.item_map['st_banco_frp'] AS st_banco_frp,
    item_row.item_map['st_agenciabanco_frp'] AS st_agenciabanco_frp,
    item_row.item_map['st_conta_frp'] AS st_conta_frp,
    item_row.item_map['st_tipoconta_frp'] AS st_tipoconta_frp,
    item_row.item_map['st_nomerecebedor_frp'] AS st_nomerecebedor_frp,
    item_row.item_map['st_cnpjrecebedor_frp'] AS st_cnpjrecebedor_frp,
    item_row.item_map['id_pessoa_pes'] AS id_pessoa_pes,
    item_row.item_map['id_forma_for'] AS id_forma_for,
    item_row.item_map['st_operacao_frp'] AS st_operacao_frp,
    item_row.item_map['vl_tarifabancaria_frp'] AS vl_tarifabancaria_frp,
    item_row.item_map['dt_diarepasse_frp'] AS dt_diarepasse_frp,
    item_row.item_map['fl_tipochavepix_frp'] AS fl_tipochavepix_frp,
    item_row.item_map['st_chavepix_frp'] AS st_chavepix_frp,
    item_row.item_map['nm_fracao_prb'] AS nm_fracao_prb,
    item_row.item_map['fl_principal_prb'] AS fl_principal_prb,
    item_row.item_map['fl_proprietario_prb'] AS fl_proprietario_prb,
    item_row.item_map['id_propsplit_pst'] AS id_propsplit_pst,
    item_row.item_map['nm_fracao_rcb'] AS nm_fracao_rcb,
    item_row.item_map['id_proprietario_pes'] AS id_proprietario_pes,
    item_row.item_map['id_usuario_usu'] AS id_usuario_usu,
    item_row.item_map['dt_alteracao_prb'] AS dt_alteracao_prb,
    item_row.item_map['nome_proprietario_formatado'] AS nome_proprietario_formatado,
    TO_JSON(item_row.item_map) AS item_payload,
    contract_row.ts_synced
FROM
    contract_row AS contract_row
LATERAL VIEW POSEXPLODE(contract_row.proprietarios_beneficiarios) item_row AS nr_item, item_map
