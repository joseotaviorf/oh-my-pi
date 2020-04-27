SELECT
    id as id,
    codigoSIAFI AS SIAFI_code,
    nomeMunicipio AS name,
    uf,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created
FROM
    datalake_ebdb_raw.`Municipio`