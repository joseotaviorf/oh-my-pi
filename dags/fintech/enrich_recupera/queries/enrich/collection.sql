SELECT
    id_creditor,
    id_customer,
    operator_name,
    historical_code AS occurrence,
    occurence_description AS occurrence_description,
    CASE
      WHEN id_creditor IN (3,5)
        AND historical_code IN ('ACORDO', 'ALEGAPGT', 'ALFRAUDE', 'ALTFONE', 'CDESCONH', 'EM FINAL', 'EMISBOL', 'EMISPIX', 'NEGOCIAC', 'PAGO', 'PROLIGAC', 'PROWHATS', 'RECADO',
        'RETCLIEN', 'SEMPREVI', 'VACORDO', 'VDIMOVEL', 'VDISCORD', 'VPINSUFI', 'VPROACOR', 'VRECADO', 'VSCONDIC','CAIXAPOS', 'CLNLOCAL', 'LIGAMUDA', 'NATENDE', 'OCUPADO', 'QUEDALIG', 'TENTESGO', 'VELOATIV', 'VSCONTAT','ALEGAPGT', 'PROLIGAC', 'RECADO', 'VMENSENV')
        THEN 1
      ELSE 0
    END AS esforco,
    CASE
        WHEN historical_code IN ('ACORDO', 'ALEGAPGT', 'ALFRAUDE', 'EM FINAL', 'NEGOCIAC', 'SEMPREVI',
        'PAGO','CDESCONH','EMISBOL', 'PROWHATS', 'PROLIGAC', 'RECADO', 'RETCLIEN')
          THEN 1

        WHEN id_creditor IN (1, 2, 4, 6, 7, 8, 9)
            AND historical_code IN ('QUITEI', 'ESTRECEB', 'PROBLE5A', 'PROMESSA', 'PROEMAIL', 'EMPROCES', 'DISCORDA',
            'NATENDE', 'OCUPADO','CAIXAPOS', 'ALTVIGENCIA', 'QUEBRAPRO', 'EM PROCESS', 'QBRACOR', 'TENTESGO', 'QUEBRAPR',
            'RETORTER','PASCHOAL','ALTVIGEN','GERALINK', 'ENVIPROP','NCONFIR','PAGOCBX','PAGOSBX','ABANDONO')
          THEN 1

        WHEN id_creditor IN (3,5)
         AND historical_code IN ('ALTFONE', 'EMISPIX', "VACORDO", "VDIMOVEL", "VDISCORD", "VPINSUFI", "VPROACOR", "VRECADO", "VSCONDIC")
          THEN 1
        ELSE 0
    END AS alo,
    CASE
        WHEN historical_code IN ('ACORDO', 'ALEGAPGT', 'EMISBOL', 'NEGOCIAC', 'PAGO', 'PROLIGAC', 'PROWHATS',
            'SEMPREVI', 'PROEMAIL')
            THEN 1
        WHEN id_creditor IN (1, 2, 4, 6, 7, 8, 9)
            AND historical_code IN ('ALFRAUDE', 'EM FINAL', 'ESTRECEB', 'PROBLE5A', 'PROMESSA',
            'QUITEI', 'EMPROCES', 'DISCORDA', 'RETCLIEN', 'ALTVIGENCIA', 'QUEBRAPRO', 'EM PROCESS',
            'QBRACOR', 'TENTESGO','QUEBRAPR','PASCHOAL', 'ALTVIGEN', 'GERALINK','ENVIPROP','NCONFIR',
            'PAGOCBX','PAGOSBX','ABANDONO')
            THEN 1
        WHEN id_creditor IN (3,5)
            AND historical_code IN ('ALTFONE', 'EMISPIX', 'VACORDO', 'VDIMOVEL', 'VDISCORD',
                'VPINSUFI', 'VPROACOR', 'VSCONDIC', 'VELOASSE', 'VELOIAF')
            THEN 1
        ELSE 0
    END AS cpc,
    CASE
        WHEN id_creditor IN (1, 2, 4, 6, 7, 8, 9)
            AND historical_code IN ('PROMESSA','PROEMAIL','PROWHATS','PROLIGAC') THEN 1 ELSE 0
    END AS promisse,
    CASE
        WHEN historical_code IN ('ACORDO','EMISBOL')
            THEN 1
        WHEN id_creditor IN (1, 2, 4, 6, 7, 8, 9)
            AND historical_code IN ('GERALINK')
            THEN 1
        WHEN id_creditor IN (3,5)
            AND historical_code IN ('EMISPIX', 'VACORDO')
            THEN 1
         ELSE 0
    END AS agreement,
    CASE
        WHEN id_creditor IN (1, 2, 4, 6, 7, 8, 9)
            AND historical_code IN ('CLNLOCAL','NATENDE','OCUPADO','FAX','LIGAMUDA','QUEDALIG') THEN 1 ELSE 0
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
