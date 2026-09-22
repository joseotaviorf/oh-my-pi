-- Nested PROPERTY.payload.contratos. Not a Superlogica HTTP extractor.
-- One row per contract listed under a unit, the shape of the RAW imoveis_contratos tab.
-- Join id_contrato_con to benvi_superlogica_contrato for the full contract payload.
WITH property_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS id_imovel_imo,
        lake_mirror.synced_at AS ts_synced,
        FROM_JSON(
            get_json_object(CAST(lake_mirror.payload AS STRING), '$.contratos'),
            'array<map<string,string>>'
        ) AS contratos
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'PROPERTY'
)
SELECT
    property_row.id,
    property_row.id_imovel_imo,
    CAST(item_row.nr_item AS INT) + 1 AS nr_item,
    item_row.item_map['id_contrato_con'] AS id_contrato_con,
    item_row.item_map['fl_ativo_con'] AS fl_ativo_con,
    item_row.item_map['dt_inicio_con'] AS dt_inicio_con,
    item_row.item_map['dt_ocupacao_con'] AS dt_ocupacao_con,
    item_row.item_map['dt_fim_con'] AS dt_fim_con,
    item_row.item_map['nm_locacoesimovel_con'] AS nm_locacoesimovel_con,
    item_row.item_map['st_label_mens'] AS st_label_mens,
    item_row.item_map['tx_adm_con'] AS tx_adm_con,
    item_row.item_map['fl_txadmvalorfixo_con'] AS fl_txadmvalorfixo_con,
    item_row.item_map['dt_ultimoreajuste_con'] AS dt_ultimoreajuste_con,
    item_row.item_map['fl_suspenso_con'] AS fl_suspenso_con,
    item_row.item_map['fl_status_con'] AS fl_status_con,
    item_row.item_map['id_tipo_con'] AS id_tipo_con,
    item_row.item_map['vl_aluguel_con'] AS vl_aluguel_con,
    item_row.item_map['nm_diarepasse_con'] AS nm_diarepasse_con,
    item_row.item_map['nm_repassegarantido_con'] AS nm_repassegarantido_con,
    item_row.item_map['fl_diafixorepasse_con'] AS fl_diafixorepasse_con,
    item_row.item_map['dt_seguroincendiofim_con'] AS dt_seguroincendiofim_con,
    item_row.item_map['id_seguradora_seg'] AS id_seguradora_seg,
    item_row.item_map['st_seguroincendioidentificador_con'] AS st_seguroincendioidentificador_con,
    item_row.item_map['fl_split_con'] AS fl_split_con,
    item_row.item_map['fl_dimob_con'] AS fl_dimob_con,
    item_row.item_map['nm_diavencimento_con'] AS nm_diavencimento_con,
    item_row.item_map['fl_garantia_con'] AS fl_garantia_con,
    item_row.item_map['st_descricaogarantia_con'] AS st_descricaogarantia_con,
    item_row.item_map['dt_garantiafim_con'] AS dt_garantiafim_con,
    item_row.item_map['vl_valorgarantia_con'] AS vl_valorgarantia_con,
    item_row.item_map['st_identificadorgarantia_con'] AS st_identificadorgarantia_con,
    item_row.item_map['fl_tipocaucaogarantia_con'] AS fl_tipocaucaogarantia_con,
    item_row.item_map['fl_garantiaresponsavel_con'] AS fl_garantiaresponsavel_con,
    item_row.item_map['dt_garantiainicio_con'] AS dt_garantiainicio_con,
    item_row.item_map['dt_seguroincendioinicio_con'] AS dt_seguroincendioinicio_con,
    item_row.item_map['fl_contratodigital_con'] AS fl_contratodigital_con,
    item_row.item_map['codigo_contrato'] AS codigo_contrato,
    item_row.item_map['detalhes_contrato'] AS detalhes_contrato,
    TO_JSON(item_row.item_map) AS item_payload,
    property_row.ts_synced
FROM
    property_row AS property_row
LATERAL VIEW POSEXPLODE(property_row.contratos) item_row AS nr_item, item_map
