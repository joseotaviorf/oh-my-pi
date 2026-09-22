-- Widened to the full MAINTENANCE_HISTORY payload so RAW manutencoes_historico in the
-- extraction spreadsheet maps one to one onto this projection.
WITH maintenance_history_row AS (
    SELECT
        id,
        vendor_natural_key,
        CAST(payload AS STRING) AS payload_json,
        synced_at
    FROM
        datalake_benvi_manager_raw.lake_mirror
    WHERE
        resource_code = 'MAINTENANCE_HISTORY'
)
SELECT
    id,
    vendor_natural_key,
    SPLIT(vendor_natural_key, '\\\\|')[0] AS id_manutencao_man,
    SPLIT(vendor_natural_key, '\\\\|')[1] AS id_historico_mhis,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_data_mhis'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_data_mhis'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_data_mhis,
    get_json_object(payload_json, '$.st_descricao_mhis') AS st_descricao_mhis,
    get_json_object(payload_json, '$.st_email_usu') AS st_email_usu,
    CAST(get_json_object(payload_json, '$.fl_tipo_mhis') AS INT) AS fl_tipo_mhis,
    get_json_object(payload_json, '$.st_descricaoapp_mhis') AS st_descricaoapp_mhis,
    synced_at AS ts_synced
FROM
    maintenance_history_row
