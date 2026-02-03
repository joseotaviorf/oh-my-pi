WITH dados_processo AS (
    SELECT
        p.id_case,
        CASE
            WHEN regexp_like(p.id_contract_cyber, '^[0-9]+(\.[0-9]+)*$') THEN p.id_contract_cyber
            ELSE NULL
        END  AS id_contract_cyber,
        COALESCE(c.id_contract_external,
                CASE
                    WHEN regexp_like(p.id_contract_cyber, '^[0-9]+(\.[0-9]+)*$') THEN p.id_contract_cyber
                    ELSE NULL
                END) as id_contract,
        p.process_type,
        p.agency_name
    FROM datalake_cyber_legal_homolog.process AS p
    LEFT JOIN datalake_cyber_legal_homolog_clean.contracts AS c
        ON p.id_contract_cyber = c.id_contract
)

SELECT
    a.id_alert,
    a.id_case,
    dp.id_contract_cyber,
    dp.id_contract,
    dp.process_type,
    a.alert_type_code,
    a.alert_comment,
    dp.agency_name,
    a.id_generating_attorney,
    a.id_revising_attorney,
    a.alert_creator,
    CASE
        WHEN a.alert_creator IS NULL THEN 'SISTEMA'
        WHEN a.alert_creator = 'SISTEMA' THEN 'SISTEMA'
        ELSE 'MANUAL'
    END AS alert_type,
    a.is_reviewed,
    CASE
        WHEN DATE(a.dt_alert_expired) >= DATE(COALESCE(a.dt_reviewed, CURRENT_DATE)) THEN 'A vencer'
        WHEN DATE(a.dt_alert_expired) < DATE(COALESCE(a.dt_reviewed, CURRENT_DATE)) THEN 'Vencida'
    END AS task_status,
    DATEDIFF(day, DATE(a.dt_alert_expired),DATE(COALESCE(a.dt_reviewed, CURRENT_DATE))) AS Lead_time,
    CASE
        WHEN DATEDIFF(day, DATE(a.dt_alert_expired), DATE(COALESCE(a.dt_reviewed, CURRENT_DATE))) = 0 THEN 'a) Vence hoje'
        WHEN DATEDIFF(day, DATE(a.dt_alert_expired), DATE(COALESCE(a.dt_reviewed, CURRENT_DATE))) BETWEEN -3 AND -1 THEN 'b) A vencer (1 a 3 dias)'
        WHEN DATEDIFF(day, DATE(a.dt_alert_expired), DATE(COALESCE(a.dt_reviewed, CURRENT_DATE))) BETWEEN -7 AND -4 THEN 'c) A vencer (4 a 7 dias)'
        WHEN DATEDIFF(day, DATE(a.dt_alert_expired), DATE(COALESCE(a.dt_reviewed, CURRENT_DATE))) < -8 THEN 'd) A vencer (8+ dias)'
        WHEN DATEDIFF(day, DATE(a.dt_alert_expired), DATE(COALESCE(a.dt_reviewed, CURRENT_DATE))) BETWEEN 1 AND 3 THEN 'e) Vencida (1 a 3 dias)'
        WHEN DATEDIFF(day, DATE(a.dt_alert_expired), DATE(COALESCE(a.dt_reviewed, CURRENT_DATE))) BETWEEN 4 AND 7 THEN 'f) Vencida (4 a 7 dias)'
        WHEN DATEDIFF(day, DATE(a.dt_alert_expired), DATE(COALESCE(a.dt_reviewed, CURRENT_DATE))) > 7 THEN 'g) Vencida (8+ dias)'
    END AS aging,
    DATE(a.dt_created),
    DATE(DATE_TRUNC('month',a.dt_created)) AS month_created,
    DATE(a.dt_alert) AS dt_alert,
    DATE(a.dt_alert_expired) AS dt_alert_expired,
    DATE(a.dt_reviewed) AS dt_reviewed
FROM datalake_cyber_legal_homolog_clean.case_alert AS a
LEFT JOIN dados_processo AS dp
    ON a.id_case = dp.id_case
