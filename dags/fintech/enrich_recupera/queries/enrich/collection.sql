SELECT
    id_creditor,
    id_customer,
    operator_name,
    historical_code AS occurrence,
    occurence_description AS occurrence_description,
    CASE
        WHEN historical_code IN ('ACORDO', 'ALEGAPGT', 'ALFRAUDE', 'EM FINAL', 'ESTRECEB', 'NEGOCIAC', 'PROBLE5A', 'PROMESSA', 'SEMPREVI', 'QUITEI', 'PROEMAIL', 'PAGO','EMPROCES', 'PROWHATS', 'DISCORDA', 'PROLIGAC', 'RETCLIEN', 'CDESCONH', 'RECADO', 'NATENDE', 'OCUPADO','CAIXAPOS', 'ALTVIGENCIA', 'QUEBRAPRO','EM PROCESS','QBRACOR', 'TENTESGO', 'CDESCONH','QUEBRAPR','RETORTER','PASCHOAL','ALTVIGEN','EMISBOL','GERALINK','ENVIPROP','NCONFIR','PAGOCBX','PAGOSBX','ABANDONO') THEN 1 ELSE 0
    END AS alo,
    CASE
        WHEN historical_code IN ('ACORDO', 'ALEGAPGT', 'ALFRAUDE', 'EM FINAL', 'ESTRECEB', 'NEGOCIAC', 'PROBLE5A', 'PROMESSA', 'SEMPREVI', 'QUITEI', 'PAGO', 'EMPROCES', 'DISCORDA', 'RETCLIEN', 'PROEMAIL', 'PROWHATS', 'PROLIGAC', 'ALTVIGENCIA', 'QUEBRAPRO', 'EM PROCESS', 'QBRACOR', 'TENTESGO','QUEBRAPR','PASCHOAL','ALTVIGEN','EMISBOL','GERALINK','ENVIPROP','NCONFIR','PAGOCBX','PAGOSBX','ABANDONO') THEN 1 ELSE 0
    END AS cpc,
    CASE
        WHEN historical_code IN ('PROMESSA','PROEMAIL','PROWHATS','PROLIGAC') THEN 1 ELSE 0
    END AS promisse,
    CASE
        WHEN historical_code IN ('ACORDO','EMISBOL','GERALINK') THEN 1 ELSE 0
    END AS agreement,
    CASE
        WHEN historical_code IN ('CLNLOCAL','NATENDE','OCUPADO','FAX','LIGAMUDA','QUEDALIG') THEN 1 ELSE 0
    END AS failure,
    ts_occurrence,
    NOW() AS ts_load,
    YEAR(CAST(ts_occurrence AS DATE)) AS year,
    MONTH(CAST(ts_occurrence AS DATE)) AS month,
    DAY(CAST(ts_occurrence AS DATE)) AS day
FROM
    datalake_recupera_clean.historical_records
WHERE
    operator_name <> 'SISTEMA'
    AND historical_code <> 'WSATUAL'
    AND year = {year}
    AND month = {month}
    AND day = {day}
