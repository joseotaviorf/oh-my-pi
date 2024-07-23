SELECT
    rev,
    CAST(from_unixtime(cast(revtstmp as bigint)/1000) as timestamp) as ts_created
FROM
    datalake_fastforward_homolog_raw.revinfo
