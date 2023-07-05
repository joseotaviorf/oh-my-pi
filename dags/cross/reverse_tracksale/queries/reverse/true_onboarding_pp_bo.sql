WITH new_contracts AS (
    SELECT
        dc.sk_contract,
        'Onboarding' AS step
    FROM
        dw_public.dim_contract AS dc
    INNER JOIN
        dw_public.fact_listing_rent_flows AS rf
            ON dc.sk_contract = rf.sk_contract
            AND rf.sk_contract_signed_date > 0
    INNER JOIN
        dw_public.dim_house_listing AS dhl
            ON dhl.sk_house_listing = rf.sk_house_listing
    LEFT JOIN
        datalake_offboarding.contract_termination ct
    	    ON dc.sk_contract = ct.id_contract
    WHERE
        dc.dt_start = DATE_ADD(current_date,-10)
        AND dhl.is_b2b = false
        AND dc.status = 'Ativo'
        AND ((ct.dt_termination > dc.dt_start) OR (ct.dt_termination IS NULL))
        AND dhl.country_code = 'BR'
        AND dhl.rental_administrator = 'OWNER' --Including only brokerage only for these metrics
    GROUP BY 1,2
),
crisis_users AS (
    SELECT
        ft.sk_contract
    FROM
        dw_tickets.dim_ticket AS dt
    INNER JOIN
        dw_tickets.fact_tickets AS ft
            ON dt.sk_ticket = ft.sk_ticket
    INNER JOIN
        datalake_gsheets_clean.department_control AS dc
            ON dt.group_name = dc.department
    WHERE
        (dc.department IN ('Notificação Extrajudicial [CE] [POS] [BACK]','Dados Bancários [CE] [POS] [BACK]','CX ReclameAqui Adquiridas [CE] [POS] [BACK]') 
            OR dc.team IN ('Casos Especiais','Ouvidoria','ReclameAqui','Evictions'))
        AND ft.sk_closed_date_local = -1
    GROUP BY 1
),
onboarding_contracts AS (
    SELECT
        c.sk_contract,
        'Onboarding' AS step
    FROM
        new_contracts AS c
    LEFT JOIN
        crisis_users AS uc
            ON uc.sk_contract = c.sk_contract
    WHERE
        uc.sk_contract IS NULL
    GROUP BY 1,2
),
owners AS (
    SELECT
        cp.cpf,
        cp.id_user,
        cp.name,
        cp.email,
        cp.phone_number,
        ac.sk_contract,
        ac.step
    FROM
        onboarding_contracts AS ac
    INNER JOIN
        datalake_ebdb_clean.contract_person AS cp
            ON ac.sk_contract = cp.id_contract
            AND cp.type in ('Proprietario')
    LEFT JOIN
        datalake_ebdb_clean.user AS u
            ON cp.email = u.email
    LEFT JOIN 
        datalake_ebdb_clean.user_pro_owner AS po 
            ON (cp.id_user = po.id_user
                OR u.id = po.id_user)
            AND po.is_active = true 
    WHERE
        po.id_user IS NULL
)
SELECT
    name AS customer_name,
    email AS customer_email,
    phone_number AS customer_phone,
    step AS campaign_step,
    'Proprietário' AS customer_type,
    cpf AS customer_cpf,
    id_user,
    'true' AS campaign_type,
    'contract' AS driver_type,
    sk_contract AS id_driver
FROM
    owners
UNION ALL
SELECT
    'Teste Disparo' AS customer_name,
    'testes.disparos.5a@gmail.com' AS customer_email,
    '+5511123456789' AS customer_phone,
    'Onboarding' AS campaign_step,
    'Proprietário' AS customer_type,
    '1234' AS customer_cpf,
    '1234' AS id_user,
    'true' AS campaign_type,
    'contract' AS driver_type,
    '1234' AS id_driver