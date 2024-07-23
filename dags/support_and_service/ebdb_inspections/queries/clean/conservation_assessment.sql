SELECT
    CAST(id AS BIGINT) AS id_conservation_assessment,
    CAST(imovelId AS BIGINT) AS id_house,
    CAST(userId AS BIGINT) AS id_user,
    CAST(jobId AS BIGINT) AS id_job,
    CAST(criadoEm AS TIMESTAMP) AS ts_created,
    CAST(atualizadoEm AS TIMESTAMP) AS ts_updated,
    CAST(startedAt AS TIMESTAMP) AS ts_started,
    CAST(finishedAt AS TIMESTAMP) AS ts_ended
FROM
    datalake_ebdb_test_raw.conservationassessment 