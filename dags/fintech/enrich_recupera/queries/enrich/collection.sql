WITH
historical_code_description AS (
    SELECT DISTINCT
        id_historical,
        historical_description
    FROM datalake_recupera_clean.historical
),
deduplicate_contract_tf AS (
    SELECT
        id,
        id_external,
        dt_start
    FROM datalake_trato_feito_clean.contract
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_external ORDER BY ts_updated DESC) = 1
),
contract_customer AS (
    SELECT DISTINCT
        COALESCE(co.id_external,c.id_contract) AS id_contract,
        COALESCE(REGEXP_REPLACE(cl.document,r"\.|\-", ""), c.id_customer) AS id_customer,
        COALESCE(co.dt_start, c.dt_contract_start) AS dt_start
    FROM datalake_trato_feito_clean.client AS cl
    LEFT JOIN deduplicate_contract_tf AS co
        ON cl.id_contract = co.id
    FULL OUTER JOIN datalake_recupera_clean.contracts AS c
        ON c.id_contract = co.id_external
        AND c.id_customer = REGEXP_REPLACE(cl.document,r"\.|\-", "")
    WHERE COALESCE(cl.creditor, c.id_creditor) IN (1,5)
),
get_contract_end_date AS (
    SELECT
        id_contract,
        id_customer,
        dt_start,
        COALESCE(LEAD(dt_start) OVER(PARTITION BY id_customer ORDER BY dt_start), CURRENT_DATE) AS dt_end
        -- Se o contrato finalizou e tem dívida, podemos cobrar até hj. Se o contrato está em aberto, podemos cobrar até hj
    FROM contract_customer
),
extract_contract AS (
    SELECT
        hr.id_creditor,
        hr.id_customer,
        NULLIF(REGEXP_EXTRACT(LOWER(hr.occurence_description), r"contrato:\s*(\d+)"), "") AS id_contract,
        hr.operator_name,
        hr.historical_code,
        h.historical_description AS occurrence,
        s.status_description AS status_occurrence,
        hr.occurence_description,
        hr.ts_occurrence,
        hr.year,
        hr.month,
        hr.day
    FROM datalake_recupera_clean.historical_records AS hr
    LEFT JOIN datalake_recupera_clean.status AS s
      ON s.id_status = hr.situation_occurrence
    LEFT JOIN historical_code_description AS h
        ON hr.historical_code = h.id_historical
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}

),
get_last_contract AS (
    SELECT
        id_creditor,
        id_customer,
        id_contract,
        LAG(id_contract) IGNORE NULLS OVER(PARTITION BY id_customer ORDER BY ts_occurrence) AS last_contract,
        operator_name,
        historical_code,
        occurrence,
        status_occurrence,
        occurence_description,
        ts_occurrence,
        year,
        month,
        day
    FROM extract_contract
)
SELECT
    id_creditor,
    glc.id_customer,
    COALESCE(glc.id_contract,last_contract,gced.id_contract) AS id_contract,
    operator_name,
    historical_code AS id_occurrence,
    occurrence,
    status_occurrence,
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
    year,
    month,
    day
FROM
    get_last_contract AS glc
LEFT JOIN get_contract_end_date AS gced
    ON glc.id_customer = gced.id_customer
    AND DATE(glc.ts_occurrence) BETWEEN gced.dt_start AND gced.dt_end
WHERE
    operator_name <> 'SISTEMA'
    AND historical_code <> 'WSATUAL'
QUALIFY ROW_NUMBER() OVER(PARTITION BY id_creditor, glc.id_customer, operator_name, historical_code, ts_occurrence ORDER BY ts_occurrence DESC) = 1
