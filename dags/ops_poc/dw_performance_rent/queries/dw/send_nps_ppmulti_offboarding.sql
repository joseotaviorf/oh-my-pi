WITH params AS (
    SELECT
        -- No Spark, current_date() é uma função. 
        -- A sintaxe de INTERVAL não exige aspas para o valor numérico em versões recentes.
        CAST(current_date() - INTERVAL 2 DAYS AS DATE) AS run_dt
),

termination_contracts AS (
    SELECT DISTINCT
        dc.sk_contract,
        'offppm' AS step
    FROM dw_rent.dim_contract dc
    INNER JOIN dw_rent.fact_listing_rent_flows rf
        ON dc.sk_contract = rf.sk_contract
       AND rf.sk_contract_signed_date > 0
    INNER JOIN dw_rent.dim_house_listing dhl
        ON dhl.sk_house_listing = rf.sk_house_listing
    LEFT JOIN datalake_offboarding.contract_termination ct
        ON dc.sk_contract = ct.id_contract
    CROSS JOIN params p
    WHERE
        CAST(ct.ts_termination_finished AS DATE) = p.run_dt
        AND dhl.is_b2b = false
        AND dhl.country_code = 'BR'
        AND ct.status = 'DONE'
        AND ct.dt_termination >= dc.dt_start
        AND dhl.rental_administrator = 'QUINTOANDAR'
    GROUP BY 1, 2
),

-- Nota: Esta CTE offboarding_contracts parece redundante pois faz o mesmo que a anterior, 
-- mas mantive para seguir sua estrutura original.
offboarding_contracts AS (
    SELECT DISTINCT
        sk_contract,
        step
    FROM termination_contracts
    GROUP BY 1, 2
),

owners AS (
    SELECT DISTINCT
        cp.cpf,
        cp.id_user,
        cp.name,
        cp.email,
        cp.phone_number,
        ac.sk_contract,
        ac.step,
        ROW_NUMBER() OVER (
            PARTITION BY cp.id_user, cp.cpf
            ORDER BY ac.sk_contract DESC
        ) AS rn
    FROM termination_contracts ac
    INNER JOIN datalake_ebdb_clean.contract_person cp
        ON ac.sk_contract = cp.id_contract
       AND cp.type IN ('Proprietario')
    LEFT JOIN datalake_ebdb_clean.user AS u
        ON (cp.email = u.email OR cp.email = u.alternative_email)
    LEFT JOIN datalake_ebdb_customer_contact_identification.customer_contact_identification AS cci
        ON cp.email = cci.customer_contact
    LEFT JOIN datalake_pp_multi.pp_multi_classification_history ppm
        ON (
               cp.id_user = ppm.id_owner
            OR u.id       = ppm.id_owner
            OR cci.id_user = ppm.id_owner
        )
       AND ppm.pp_multi_classification = 'ACTIVE'
       -- AJUSTE: No Spark, usamos make_date para converter colunas de ano/mes/dia em DATE
       AND make_date(CAST(ppm.year AS INT), CAST(ppm.month AS INT), CAST(ppm.day AS INT)) = current_date() - INTERVAL 1 DAY
    WHERE
        ppm.id_owner IS NOT NULL
),

open_onboarding_users AS (
    SELECT DISTINCT
        cp.id_user as sk_user  
    FROM dw_rent.dim_contract dc
    INNER JOIN datalake_ebdb_clean.contract_person cp
        ON dc.sk_contract = cp.id_contract 
    CROSS JOIN params p
    WHERE
        CAST(dc.dt_start AS DATE) >= date_trunc('month', p.run_dt)
        AND CAST(dc.dt_start AS DATE) <= p.run_dt
        AND dc.status = 'Ativo'  
        AND cp.type = 'Proprietario'
),

quarantine_users AS (
    SELECT DISTINCT
        cp.id_user
    FROM dw_rent.dim_contract dc
    INNER JOIN datalake_offboarding.contract_termination ct
        ON dc.sk_contract = ct.id_contract
    INNER JOIN datalake_ebdb_clean.contract_person cp
        ON dc.sk_contract = cp.id_contract
       AND cp.type = 'Proprietario'
    INNER JOIN dw_rent.fact_listing_rent_flows rf
        ON dc.sk_contract = rf.sk_contract
    INNER JOIN dw_rent.dim_house_listing dhl
        ON dhl.sk_house_listing = rf.sk_house_listing
    CROSS JOIN params p
    WHERE
        dhl.is_b2b = false
        AND dhl.country_code = 'BR'
        AND dhl.rental_administrator = 'QUINTOANDAR'
        AND ct.status = 'DONE'
        -- AJUSTE: Sintaxe de INTERVAL simplificada
        AND CAST(ct.ts_termination_finished AS DATE) 
            BETWEEN p.run_dt - INTERVAL 32 DAYS AND p.run_dt - INTERVAL 3 DAYS
)

SELECT DISTINCT
    o.name AS customer_name,
    o.email AS customer_email,
    o.phone_number AS customer_phone,
    o.step AS campaign_step,
    'Proprietário' AS customer_type,
    o.cpf AS customer_cpf,
    o.id_user,
    'ppm' AS campaign_type,
    'contract' AS driver_type,
    o.sk_contract AS id_driver,
        concat(
        o.email, ' ',
        date_format(CAST(date_trunc('month', current_date()) AS TIMESTAMP), 'yyyy-MM')
    ) AS chave,
    NOW() AS ts_load
FROM owners o
LEFT JOIN open_onboarding_users otu
    ON otu.sk_user = o.id_user   
LEFT JOIN quarantine_users qu
    ON qu.id_user = o.id_user
WHERE
    otu.sk_user IS NULL
    AND qu.id_user IS NULL
    AND o.rn = 1;