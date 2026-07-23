WITH
cyber_base AS (
    SELECT
        id_customer,
        id_contract_external AS id_contract,
        id_operator,
        operator_agency,
        CASE
            WHEN creditor = "QuintoAndar" THEN "IQ QuintoAndar"
        END AS creditor,
        CASE
            WHEN action_description = 'Migração' THEN 'Cyber (Migração)'
            ELSE 'Cyber'
        END AS source,
        phone_number,
        action,
        action_code_type,
        action_description,
        result,
        result_code_type,
        result_description,
        complement,
        complement_code_type,
        complement_description,
        occurrence_description,
        esforco,
        alo,
        cpc,
        promessa AS promisse,
        promessa AS agreement,
        ts_occurrence
    FROM datalake_cyber.collection
    WHERE INT(contract_group) = 1
),
recupera_base AS (
    SELECT
        id_customer,
        id_contract,
        UPPER(operator_name) AS id_operator,
        CASE
            WHEN operator_name LIKE "%WHELP%" THEN "WEBHELP"
        END AS operator_agency,
        CASE
            WHEN id_creditor IN (1,4,7,8,9) THEN "IQ QuintoAndar"
            WHEN id_creditor IN (2,6) THEN "PP QuintoAndar"
        END AS creditor,
        'Recupera' AS source,
        2 AS priority,
        UPPER(id_occurrence) AS action,
        UPPER(occurrence) AS action_description,
        REPLACE(occurrence_description, '/',' ') AS occurrence_description,
        esforco,
        alo,
        cpc,
        promisse,
        agreement,
        failure,
        ts_occurrence
    FROM datalake_recupera.collection
    WHERE id_creditor NOT IN (3,5)
),
union_logs AS (
    SELECT
        COALESCE(c.id_customer, r.id_customer) AS id_customer,
        COALESCE(c.id_contract, r.id_contract) AS id_contract,
        COALESCE(c.id_operator, r.id_operator) AS id_operator,
        COALESCE(c.creditor, r.creditor) AS creditor,
        COALESCE(o.company_name, c.operator_agency, r.operator_agency) AS operator_agency,
        CONCAT_WS(" | ", c.source, r.source) AS source,
        c.phone_number,
        CASE
            WHEN c.source = 'Cyber (Migração)' THEN COALESCE(r.action, c.action)
            ELSE COALESCE(c.action, r.action)
        END AS action,
        c.action_code_type,
        c.action_description,
        c.result,
        c.result_code_type,
        c.result_description,
        c.complement,
        c.complement_code_type,
        c.complement_description,
        COALESCE(c.occurrence_description, r.occurrence_description) AS occurrence_description,
        COALESCE(c.esforco, r.esforco) AS esforco,
        COALESCE(c.alo, r.alo) AS alo,
        COALESCE(c.cpc, r.cpc) AS cpc,
        COALESCE(c.promisse, r.promisse) AS promisse,
        COALESCE(c.agreement, r.agreement) AS agreement,
        r.failure,
        COALESCE(c.ts_occurrence, r.ts_occurrence) AS ts_occurrence
    FROM cyber_base AS c
    FULL OUTER JOIN recupera_base AS r
        ON COALESCE(c.id_contract, 0) = COALESCE(r.id_contract, 0)
        AND c.creditor = r.creditor
        AND COALESCE(c.id_operator, '') = COALESCE(r.id_operator, '')
        AND c.ts_occurrence = r.ts_occurrence
    LEFT JOIN datalake_collections_quintoandar.operators AS o
        ON COALESCE(c.id_operator, r.id_operator) = o.id_operator
)
SELECT
    md5(CONCAT(id_customer, COALESCE(id_contract,0), creditor, COALESCE(id_operator, ''),
                COALESCE(phone_number, ''), COALESCE(action, ''), COALESCE(result, ''),
                COALESCE(complement, ''), occurrence_description, ts_occurrence)) AS id_collection,
    id_customer,
    id_contract,
    creditor,
    id_operator,
    operator_agency,
    phone_number,
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
    occurrence_description,
    esforco,
    alo,
    cpc,
    promisse,
    agreement,
    failure,
    ts_occurrence,
    NOW() AS ts_load
FROM union_logs AS l
