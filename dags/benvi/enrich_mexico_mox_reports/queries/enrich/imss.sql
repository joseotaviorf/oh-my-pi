SELECT
    GET_JSON_OBJECT(aud.attributes, "$.IMSS.curp") AS curp,
    BIGINT(GET_JSON_OBJECT(aud.attributes, "$.IMSS.nss")) AS nss,
    GET_JSON_OBJECT(aud.attributes, "$.IMSS.data.nombre") AS name,
    aud.presumed_income,
    INT(GET_JSON_OBJECT(aud.attributes, "$.IMSS.data.semanasCotizadas.semanasCotizadas")) AS weeks_worked,
    INT(GET_JSON_OBJECT(aud.attributes, "$.IMSS.data.semanasCotizadas.semanasDescontadas")) AS weeks_discounted,
    INT(GET_JSON_OBJECT(aud.attributes, "$.IMSS.data.semanasCotizadas.semanasReintegradas")) AS weeks_recovered,
    rev.ts_created AS ts_report,
    rev.year,
    rev.month,
    rev.day
FROM
    datalake_arquivo_confidencial_clean.presumed_income_report_aud AS aud
JOIN
    datalake_arquivo_confidencial_clean.rev_info AS rev
        ON rev.rev = aud.rev
WHERE
    rev.year = {year}
    AND rev.month = {month}
    AND rev.day = {day}
    AND source = 'MOX'
    AND attributes LIKE '%IMSS%'
