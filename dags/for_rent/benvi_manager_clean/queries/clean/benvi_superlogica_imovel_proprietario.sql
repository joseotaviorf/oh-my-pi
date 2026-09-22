-- Nested PROPERTY.payload.proprietarios_beneficiarios. Not a Superlogica HTTP extractor.
-- One row per beneficiary owner of a unit, the shape of the RAW imoveis_proprietarios tab.
-- Join id_pessoa_pes to benvi_superlogica_proprietario.
WITH property_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS id_imovel_imo,
        lake_mirror.synced_at AS ts_synced,
        FROM_JSON(
            get_json_object(CAST(lake_mirror.payload AS STRING), '$.proprietarios_beneficiarios'),
            'array<map<string,string>>'
        ) AS proprietarios_beneficiarios
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'PROPERTY'
)
SELECT
    property_row.id,
    property_row.id_imovel_imo,
    CAST(item_row.nr_item AS INT) + 1 AS nr_item,
    item_row.item_map['id_gestor_ges'] AS id_gestor_ges,
    item_row.item_map['st_nome_ges'] AS st_nome_ges,
    item_row.item_map['st_email_ges'] AS st_email_ges,
    item_row.item_map['st_celular_ges'] AS st_celular_ges,
    item_row.item_map['st_fantasia_pes'] AS st_fantasia_pes,
    item_row.item_map['st_nome_pes'] AS st_nome_pes,
    item_row.item_map['id_pessoa_pes'] AS id_pessoa_pes,
    item_row.item_map['id_formarecebimento_pes'] AS id_formarecebimento_pes,
    item_row.item_map['st_banco_pes'] AS st_banco_pes,
    item_row.item_map['st_conta_pes'] AS st_conta_pes,
    item_row.item_map['st_agenciabanco_pes'] AS st_agenciabanco_pes,
    item_row.item_map['st_tipoconta_pes'] AS st_tipoconta_pes,
    item_row.item_map['st_operacao_pes'] AS st_operacao_pes,
    item_row.item_map['st_nomerecebedor_pes'] AS st_nomerecebedor_pes,
    item_row.item_map['st_cnpjrecebedor_pes'] AS st_cnpjrecebedor_pes,
    item_row.item_map['st_cnpj_pes'] AS st_cnpj_pes,
    item_row.item_map['id_sacado_sac'] AS id_sacado_sac,
    item_row.item_map['dt_nascimento_pes'] AS dt_nascimento_pes,
    item_row.item_map['st_email_pes'] AS st_email_pes,
    item_row.item_map['st_celular_pes'] AS st_celular_pes,
    item_row.item_map['dt_diarepasse_pes'] AS dt_diarepasse_pes,
    item_row.item_map['id_proprietario_pes'] AS id_proprietario_pes,
    item_row.item_map['fl_principal_prb'] AS fl_principal_prb,
    item_row.item_map['fl_proprietario_prb'] AS fl_proprietario_prb,
    item_row.item_map['nm_fracao_prb'] AS nm_fracao_prb,
    item_row.item_map['nm_fracao_rcb'] AS nm_fracao_rcb,
    item_row.item_map['id_formarecebimento_frp'] AS id_formarecebimento_frp,
    item_row.item_map['id_formapagamento'] AS id_formapagamento,
    item_row.item_map['nome_formatado'] AS nome_formatado,
    item_row.item_map['pessoas'] AS pessoas,
    TO_JSON(item_row.item_map) AS item_payload,
    property_row.ts_synced
FROM
    property_row AS property_row
LATERAL VIEW POSEXPLODE(property_row.proprietarios_beneficiarios) item_row AS nr_item, item_map
