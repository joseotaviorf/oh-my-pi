SELECT 
    CAST(id AS BIGINT) AS id_conservation_room,
    CAST(assessmentId AS BIGINT) AS id_assessment,
    roomType AS room_type,
    CAST(criadoEm AS TIMESTAMP) AS ts_created,
    CAST(atualizadoEm AS TIMESTAMP) AS ts_updated
FROM
    datalake_ebdb_raw.conservationroom