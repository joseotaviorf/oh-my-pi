-- Nested CONTRACT.payload.imoveis_gestores. Not a Superlogica HTTP extractor.
-- One row per assigned property manager, the shape of the RAW contratos_gestores tab.
-- nr_item = 1 is the Gestor principal the imovel projection denormalizes.
WITH contract_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS id_contrato_con,
        lake_mirror.synced_at AS ts_synced,
        FROM_JSON(
            get_json_object(CAST(lake_mirror.payload AS STRING), '$.imoveis_gestores'),
            'array<map<string,string>>'
        ) AS imoveis_gestores
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'CONTRACT'
)
SELECT
    contract_row.id,
    contract_row.id_contrato_con,
    CAST(item_row.nr_item AS INT) + 1 AS nr_item,
    item_row.item_map['id_gestor_ges'] AS id_gestor_ges,
    item_row.item_map['st_nome_ges'] AS st_nome_ges,
    item_row.item_map['st_email_ges'] AS st_email_ges,
    item_row.item_map['st_celular_ges'] AS st_celular_ges,
    item_row.item_map['id_imovel_imo'] AS id_imovel_imo,
    TO_JSON(item_row.item_map) AS item_payload,
    contract_row.ts_synced
FROM
    contract_row AS contract_row
LATERAL VIEW POSEXPLODE(contract_row.imoveis_gestores) item_row AS nr_item, item_map
