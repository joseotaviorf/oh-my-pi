WITH contrato AS (
    WITH base AS (
        SELECT 
            ac.id_agent AS agent_id,
            du.id AS user_id,
            ac.ts_work_contract_started,
            rank() OVER (PARTITION BY ac.id_agent ORDER BY ac.ts_work_contract_started DESC) AS rn
        FROM 
            datalake_ebdb_agents.agent_contract ac
        JOIN 
            dw_public.dim_user du 
                ON du.dados_agente_id = ac.id_agent
  )
    SELECT 
        agent_id,
        user_id,
        ts_work_contract_started
    FROM 
        base
    WHERE 
        rn = 1 
),
dados_agent AS (
    SELECT 
        du.sk_user,
        du.nome, 
        du.cpf,
        ROW_NUMBER() OVER (PARTITION BY du.cpf ORDER BY du.dadosagente_ativo DESC, c.ts_work_contract_started ) AS first_or_active_id
    FROM 
        dw_public.dim_user du
    LEFT JOIN 
        contrato c
            ON c.user_id = du.sk_user
    WHERE 
        du.is_rent_agent IS true 
        OR du.is_sale_agent IS true
)
SELECT 
    sk_user,
    nome, 
    cpf,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM 
    dados_agent
WHERE first_or_active_id = 1
