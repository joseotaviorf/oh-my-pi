SELECT
    GET_JSON_OBJECT(aud.attributes, "$.IMSS.curp") AS curp,
    BIGINT(GET_JSON_OBJECT(aud.attributes, "$.IMSS.nss")) AS nss,
    GET_JSON_OBJECT(aud.attributes, "$.IMSS.data.nombre") AS name,
    aud.presumed_income,
    INT(GET_JSON_OBJECT(aud.attributes, "$.IMSS.data.semanasCotizadas.semanasCotizadas")) AS weeks_worked,
    INT(GET_JSON_OBJECT(aud.attributes, "$.IMSS.data.semanasCotizadas.semanasDescontadas")) AS weeks_discounted,
    INT(GET_JSON_OBJECT(aud.attributes, "$.IMSS.data.semanasCotizadas.semanasReintegradas")) AS weeks_recovered,
    MAX(rev.ts_created) AS ts_report,
    YEAR(MAX(rev.ts_created)) AS year,
    MONTH(MAX(rev.ts_created)) AS month,
    DAY(MAX(rev.ts_created)) AS day
FROM
    datalake_arquivo_confidencial_clean.presumed_income_report_aud AS aud
JOIN
    datalake_arquivo_confidencial_clean.rev_info AS rev
        ON rev.rev = aud.rev
WHERE
    source = 'MOX'
    AND attributes LIKE '%IMSS%'
GROUP BY
    1, 2, 3, 4, 5, 6, 7
