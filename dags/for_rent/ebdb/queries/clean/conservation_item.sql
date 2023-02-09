SELECT 
    CAST(id AS BIGINT) AS id_conservation_item,
    CAST(roomId AS BIGINT) AS id_room,
    itemType AS item_type,
    itemGroup AS item_group,
    CAST(COALESCE(present, FALSE) AS BOOLEAN) AS is_present,
    CAST(criadoEm AS TIMESTAMP) AS ts_created,
    CAST(atualizadoEm AS TIMESTAMP) AS ts_updated
FROM 
    datalake_ebdb_raw.conservationitem