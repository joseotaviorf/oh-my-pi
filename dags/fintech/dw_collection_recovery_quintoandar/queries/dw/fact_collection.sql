WITH
collection_calculation AS (
    SELECT
        c.id_customer AS sk_debtor,
        c.id_contract,
        CASE
        WHEN c.id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
        WHEN c.id_creditor IN (2,6) THEN "PP QuintoAndar"
        END AS creditor,
        UPPER(c.operator_name) AS id_operator,
        o.id_operator_registration,
        UPPER(c.id_occurrence) AS id_occurrence,
        UPPER(c.occurrence) AS occurrence,
        DATE(c.ts_occurrence) AS dt_occurrence,
        INT(SUM(c.esforco)) AS total_esforco,
        INT(SUM(c.alo)) AS total_alo,
        INT(SUM(c.cpc)) AS total_cpc,
        INT(SUM(c.promisse)) AS total_promisse,
        INT(SUM(c.agreement)) AS total_agreement,
        INT(SUM(c.failure)) AS total_failure
    FROM datalake_recupera.collection AS c
    LEFT JOIN datalake_recupera_clean.operators AS o
        ON UPPER(c.operator_name) = UPPER(o.id_operator)
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND c.id_creditor NOT IN (3,5)
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
)
SELECT
    md5(CONCAT(sk_debtor, COALESCE(id_contract,0), creditor, id_operator, id_occurrence, dt_occurrence)) AS sk_collection,
    sk_debtor,
    id_contract AS sk_contract,
    id_operator,
    id_operator_registration,
    id_occurrence,
    creditor,
    occurrence,
    total_esforco,
    total_alo,
    total_cpc,
    total_promisse,
    total_agreement,
    total_failure,
    dt_occurrence,
    YEAR(dt_occurrence) AS year,
    MONTH(dt_occurrence) AS month,
    DAY(dt_occurrence) AS day,
    NOW() AS ts_load
FROM collection_calculation
