SELECT
    id,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    details,
    problem,
    successful as is_successful
FROM
    datalake_ebdb_test_raw.`Entrance`
