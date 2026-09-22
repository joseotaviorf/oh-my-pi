-- Nested PROPERTY.payload.imoveis_gestores. Not a Superlogica HTTP extractor.
-- One row per assigned property manager, the shape of the RAW imoveis_gestores tab.
-- nr_item = 1 is the Gestor principal the imovel projection denormalizes.
WITH property_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS id_imovel_imo,
        lake_mirror.synced_at AS ts_synced,
        FROM_JSON(
            get_json_object(CAST(lake_mirror.payload AS STRING), '$.imoveis_gestores'),
            'array<map<string,string>>'
        ) AS imoveis_gestores
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
    item_row.item_map['st_email_ges'] AS st_email_ges,
    item_row.item_map['st_nome_ges'] AS st_nome_ges,
    item_row.item_map['st_celular_ges'] AS st_celular_ges,
    item_row.item_map['st_departamentos'] AS st_departamentos,
    TO_JSON(item_row.item_map) AS item_payload,
    property_row.ts_synced
FROM
    property_row AS property_row
LATERAL VIEW POSEXPLODE(property_row.imoveis_gestores) item_row AS nr_item, item_map
