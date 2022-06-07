WITH crisis_contracts AS (
    SELECT
        ft.sk_contract
    FROM
        dw_tickets.dim_ticket dt
    INNER JOIN
        dw_tickets.fact_tickets ft
            ON dt.sk_ticket = ft.sk_ticket
    INNER JOIN
        datalake_gsheets_clean.department_control dc
            ON dt.group_name = dc.department
    WHERE
        dc.team IN ('Casos Especiais','Ouvidoria','Proteção 5A','ReclameAqui','Evictions')
        AND ft.sk_solved_date_local = -1
    GROUP BY 1
),
offboarding_contracts_wo_ticket AS (
    WITH termination_requests_done AS (
        SELECT
            ct.sk_contract,
            DATEDIFF(current_date, ct.ts_termination_finished) AS days_since_finished
        FROM
            dw_datamarts_for_rent.contract_termination ct
        LEFT JOIN
            crisis_contracts cc
                ON cc.sk_contract = ct.sk_contract
        LEFT JOIN
            dw_public.fact_house_listings fhl
                ON ct.sk_contract = fhl.sk_contract
        LEFT JOIN
            dw_public.dim_contract dc
                ON ct.sk_contract = dc.sk_contract
        WHERE ct.status = 'DONE'
            AND cc.sk_contract IS NULL
            AND fhl.sk_partner = -1
            AND ct.dt_termination > dc.dt_start
            AND dc.country_code = 'BR'
    )
    SELECT
        sk_contract,
        'Rescisão' AS step
    FROM
        termination_requests_done
    WHERE
        days_since_finished = 2
),
tenants_dwellers AS (
    SELECT
        cp.cpf,
        cp.id_user,
        cp.name,
        cp.email,
        cp.phone_number,
        oc.sk_contract,
        oc.step,
        DENSE_RANK() OVER(PARTITION BY cp.id_contract, cp.email ORDER BY cp.id) AS order_diff_email
    FROM
        offboarding_contracts_wo_ticket oc
    INNER JOIN
        datalake_ebdb_clean.contract_person cp
            ON oc.sk_contract = cp.id_contract
            AND cp.type IN ('Inquilino','Morador')
            AND cp.email IS NOT NULL
)
SELECT
    name AS customer_name,
    email AS customer_email,
    phone_number AS customer_phone,
    step AS campaign_step,
    'Inquilino' AS customer_type,
    cpf AS customer_cpf,
    id_user,
    'true' AS campaign_type,
    'contract' AS driver_type,
    sk_contract AS id_driver
FROM
    tenants_dwellers
WHERE
    order_diff_email = 1
UNION ALL
SELECT
    'Teste Disparo' AS customer_name,
    'testes.disparos.5a@gmail.com' AS customer_email,
    '+5511123456789' AS customer_phone,
    'Rescisão' AS campaign_step,
    'Inquilino' AS customer_type,
    '12345' AS customer_cpf,
    '12345' AS id_user,
    'true' AS campaign_type,
    'contract' AS driver_type,
    '12345' AS id_driver
