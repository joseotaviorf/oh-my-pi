SELECT
    CAST(id AS BIGINT) AS id_conservation_item_functional,
    CAST(itemId AS BIGINT) AS id_item,
    isFunctional AS functional_answer,
    comment,
    CAST(criadoEm AS TIMESTAMP) AS ts_created,
    CAST(atualizadoEm AS TIMESTAMP) AS ts_updated
FROM
    datalake_ebdb_raw.conservationitemfunctional