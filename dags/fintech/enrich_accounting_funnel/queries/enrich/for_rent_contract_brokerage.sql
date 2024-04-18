WITH contract_partnership_data AS (
    SELECT
        id_contract,
        partner_type,
        brokerage_split_percentage
    FROM 
        datalake_ebdb_clean.contract_partnership_data
    QUALIFY 
        ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY id DESC) = 1
),

first_rent_from_contract AS (
    SELECT
        id_contract,
        rent
    FROM 
        datalake_ebdb_clean.contract_aud
    QUALIFY 
        ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY rev) = 1
),

agents_by_contract AS (
    SELECT
        con.id AS id_contract,
        COALESCE(COUNT(DISTINCT b.id_agent), 0) AS num_agents
    FROM 
        datalake_ebdb_rent_flow.rent_flow a
    INNER JOIN 
        datalake_ebdb_clean.contract AS con
          ON con.id_house = a.id_house
          AND con.id = a.id_contract
    LEFT JOIN 
        datalake_ebdb_clean.agent_rent_flow b
          ON a.id_rent_flow = b.id_rent_flow
    WHERE
        con.status NOT IN ('Minuta', 'PreAssinaturas', 'Cancelado')
        AND con.type = 'FullService'
    GROUP BY 1
),

df AS (
    SELECT
        c.id AS id_contract,
        contract_rent_model:rentalAdministrator AS rental_administrator,
        ROUND(f_rent.rent,2) AS rent,
        c.fist_rent_comission_fee AS first_rent_commission_fee,
        CASE
            WHEN a.num_agents = 0 THEN NULL
            WHEN a.num_agents = 1 THEN NULLIF(c.agent_brokerage_share, 0.00)
            WHEN a.num_agents > 1 THEN 0.20
        END AS agent_brokerage_share,
        NULLIF(IF(contract_rent_model:rentalAdministrator = 'THIRD_PARTY', NULL, p.brokerage_split_percentage), 0.00) AS ciq_brokerage_share,
        NULLIF(IF(contract_rent_model:rentalAdministrator = 'THIRD_PARTY', NULL, pp.brokerage_split_percentage), 0.00) AS select_brokerage_share,
        NULLIF(IF(contract_rent_model:rentalAdministrator = 'THIRD_PARTY', 0.5, NULL), 0) AS 3p_brokerage_share,
        NULLIF(f_rent.rent *
        (CASE
            WHEN a.num_agents = 0 THEN 0.00
            WHEN a.num_agents = 1 THEN c.agent_brokerage_share
            WHEN a.num_agents > 1 THEN 0.20
        END), 0.00) AS agent_brokerage_amount,
        NULLIF(IF(contract_rent_model:rentalAdministrator = 'THIRD_PARTY', NULL, f_rent.rent * c.fist_rent_comission_fee * p.brokerage_split_percentage), 0.00) AS ciq_brokerage_amount,
        NULLIF(IF(contract_rent_model:rentalAdministrator = 'THIRD_PARTY', NULL, f_rent.rent * c.fist_rent_comission_fee * pp.brokerage_split_percentage), 0.00) AS select_brokerage_amount,
        NULLIF(f_rent.rent * c.fist_rent_comission_fee * IF(contract_rent_model:rentalAdministrator = 'THIRD_PARTY', 0.5, NULL), 0) AS 3p_brokerage_amount,
        c.dt_started AS dt_contract_started
    FROM 
        datalake_ebdb_clean.contract c
    LEFT JOIN 
        contract_partnership_data p
            ON c.id = p.id_contract
            AND p.partner_type = 'AUTONOMOUS_AGENT'
    LEFT JOIN 
        contract_partnership_data pp
            ON c.id = pp.id_contract
            AND pp.partner_type = 'EXECUTIVE_FOR_RENT'
    LEFT JOIN 
        first_rent_from_contract f_rent
            ON f_rent.id_contract = c.id
    LEFT JOIN 
        agents_by_contract a
            ON a.id_contract = c.id
)

SELECT
    id_contract,
    rent,
    first_rent_commission_fee,
    IF(rental_administrator != 'THIRD_PARTY', ROUND(1.00 - (COALESCE(agent_brokerage_share, 0) + COALESCE(ciq_brokerage_share, 0) + COALESCE(select_brokerage_share, 0) + COALESCE(3p_brokerage_share, 0)),3), ROUND(1.00 - (COALESCE(agent_brokerage_share, 0) + COALESCE(3p_brokerage_share, 0)),3)) AS 5A_brokerage_share,
    ROUND(agent_brokerage_share,3) AS agent_brokerage_share,
    ROUND(ciq_brokerage_share,3) AS ciq_brokerage_share,
    ROUND(select_brokerage_share,3) AS select_brokerage_share,
    ROUND(3p_brokerage_share,3) AS 3p_brokerage_share,
    IF(rental_administrator != 'THIRD_PARTY', ROUND((rent * first_rent_commission_fee) - COALESCE(agent_brokerage_amount, 0) - COALESCE(ciq_brokerage_amount, 0) - COALESCE(select_brokerage_amount, 0) - COALESCE(3p_brokerage_amount, 0), 2), ROUND((rent * first_rent_commission_fee) - COALESCE(agent_brokerage_amount, 0) - COALESCE(3p_brokerage_amount, 0), 2)) AS 5A_brokerage_amount,
    ROUND(agent_brokerage_amount,2) AS agent_brokerage_amount,
    ROUND(ciq_brokerage_amount,2) AS ciq_brokerage_amount,
    ROUND(select_brokerage_amount,2) AS select_brokerage_amount,
    ROUND(3p_brokerage_amount,2) AS 3p_brokerage_amount,
    dt_contract_started
FROM 
    df