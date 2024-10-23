WITH
union_collection AS (
    SELECT
        id_customer,
        id_contract_external AS id_contract,
        id_operator,
        operator_agency,
        "IQ QuintoAndar" AS creditor,
        action,
        action_code_type,
        action_description,
        result,
        result_code_type,
        result_description,
        complement,
        complement_code_type,
        complement_description,
        DATE(ts_occurrence) AS dt_occurrence,
        SUM(IFNULL(esforco,0)) AS total_esforco,
        SUM(IFNULL(alo,0)) AS total_alo,
        SUM(IFNULL(cpc,0)) AS total_cpc,
        0 AS total_promisse,
        SUM(IFNULL(acordo,0)) AS total_agreement,
        0 AS total_failure,
        'Cyber' AS source,
        1 AS priority
    FROM datalake_cyber.collection
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15

    UNION DISTINCT

    SELECT
        c.id_customer,
        c.id_contract,
        UPPER(c.operator_name) AS id_operator,
        o.id_operator_registration AS operator_agency,
        CASE
            WHEN c.id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
            WHEN c.id_creditor IN (2,6) THEN "PP QuintoAndar"
        END AS creditor,
        UPPER(c.id_occurrence) AS action,
        NULL AS action_code_type,
        UPPER(c.occurrence) AS action_description,
        NULL AS result,
        NULL AS result_code_type,
        NULL AS result_description,
        NULL AS complement,
        NULL AS complement_code_type,
        NULL AS complement_description,
        DATE(c.ts_occurrence) AS dt_occurrence,
        SUM(IFNULL(c.esforco,0)) AS total_esforco,
        SUM(IFNULL(c.alo,0)) AS total_alo,
        SUM(IFNULL(c.cpc,0)) AS total_cpc,
        SUM(IFNULL(c.promisse,0)) AS total_promisse,
        SUM(IFNULL(c.agreement,0)) AS total_agreement,
        SUM(IFNULL(c.failure,0)) AS total_failure,
        'Recupera' AS source,
        2 AS priority
    FROM datalake_recupera.collection AS c
    LEFT JOIN datalake_recupera_clean.operators AS o
        ON UPPER(c.operator_name) = UPPER(o.id_operator)
    WHERE c.id_creditor NOT IN (3,5)
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15

)
SELECT
    md5(CONCAT(id_customer, COALESCE(id_contract,0), creditor, id_operator, action, dt_occurrence)) AS sk_collection,
    id_customer AS sk_debtor,
    id_contract AS sk_contract,
    id_operator,
    operator_agency,
    source,
    action,
    action_code_type,
    action_description,
    result,
    result_code_type,
    result_description,
    complement,
    complement_code_type,
    complement_description,
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
FROM union_collection
QUALIFY ROW_NUMBER() OVER(PARTITION BY CONCAT(id_customer, COALESCE(id_contract,0), creditor, id_operator, action, dt_occurrence) ORDER BY priority) = 1
