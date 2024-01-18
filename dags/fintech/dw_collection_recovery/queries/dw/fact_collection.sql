WITH historical_code_description AS (
    SELECT DISTINCT
        id_historical,
        historical_description
    FROM datalake_recupera_clean.historical
),
collection_calculation AS (
    SELECT
        DENSE_RANK() OVER(ORDER BY c.ts_occurrence) AS sk_collection,
        c.id_customer AS sk_debtor,
        CASE
        WHEN c.id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
        WHEN c.id_creditor IN (3,5) THEN "IQ QuintoCred"
        WHEN c.id_creditor IN (2,6) THEN "PP QuintoAndar"
        END AS creditor,
        UPPER(c.operator_name) AS id_operator,
        o.id_operator_registration,
        UPPER(c.occurrence) AS id_occurrence,
        UPPER(h.historical_description) AS occurrence,
        DATE(c.ts_occurrence) AS dt_occurrence,
        c.alo,
        c.cpc,
        c.promisse,
        c.agreement,
        c.failure,
        c.esforco
    FROM datalake_recupera.collection AS c
    LEFT JOIN datalake_recupera_clean.operators AS o
        ON c.operator_name = o.id_operator
    LEFT JOIN historical_code_description AS h
        ON c.occurrence = h.id_historical
)
SELECT
    sk_collection,
    sk_debtor,
    creditor,
    id_operator,
    id_operator_registration,
    id_occurrence,
    occurrence,
    INT(SUM(esforco)) AS total_esforco,
    INT(SUM(alo)) AS total_alo,
    INT(SUM(cpc)) AS total_cpc,
    INT(SUM(promisse)) AS total_promisse,
    INT(SUM(agreement)) AS total_agreement,
    INT(SUM(failure)) AS total_failure,
    dt_occurrence,
    YEAR(dt_occurrence) AS year,
    MONTH(dt_occurrence) AS month,
    DAY(dt_occurrence) AS day,
    NOW() AS ts_load
FROM collection_calculation
GROUP BY 1, 2, 3, 4, 5, 6, 7, 14
