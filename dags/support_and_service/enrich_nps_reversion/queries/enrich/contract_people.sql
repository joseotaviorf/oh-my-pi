WITH tenants AS (
    SELECT DISTINCT
        sk_contract,
        sk_user
    FROM
        dw_quintoandar.fact_contract_people
    WHERE 
        contract_role = 'tenant'
    UNION
    SELECT DISTINCT
        ft.sk_contract,
        ft.sk_user
    FROM
        dw_customer_support.fact_ticket AS ft
    LEFT JOIN 
        dw_customer_support.dim_taxonomy AS dt 
            ON ft.sk_taxonomy = dt.sk_taxonomy
    WHERE
        sk_contract IS NOT NULL
        AND dt.customer_type_tag = 'tenant'
),
tenants_adjusted AS (
    SELECT
        ct.id_contract,
        tenants.sk_user,
        DATE(ct.ts_created) AS dt_reference,
        'offboarding_tenant' AS model_name,
        'nps_reversion_off_tenant_reglog_v0' AS model_version,
        dc.ts_created AS ts_tickets_search_range_min,
        ct.ts_created AS ts_tickets_search_range_max
    FROM
        datalake_offboarding.contract_termination AS ct
    LEFT JOIN
        dw_public.dim_contract AS dc
            ON dc.sk_contract = ct.id_contract
    LEFT JOIN
        tenants
            ON tenants.sk_contract = ct.id_contract
    WHERE
        DATE(ct.ts_created) = DATE('{year}-{month}-{day}')
        AND ct.status <> 'CANCELED'
        AND sk_user IS NOT NULL
        AND sk_user <> -1
),
people AS (
    SELECT 
        fcp.sk_contract,
        fcp.sk_contract_person,
        dcp.personal_document,
        fcp.contract_role,
        fcp.sk_user,
        dcp.phone_number,
        dcp.email,
        dc.ts_created
    FROM
        dw_quintoandar.fact_contract_people AS fcp
    LEFT JOIN
        dw_quintoandar.dim_contract_person AS dcp
            ON dcp.sk_contract_person = fcp.sk_contract_person
    LEFT JOIN
        dw_public.dim_contract AS dc
            ON dc.sk_contract = fcp.sk_contract
    WHERE
        fcp.contract_role IN ('tenant', 'landlord', 'dweller')
),
contract_people_togather AS (
    SELECT
        people.sk_contract,
        people.sk_contract_person,
        people.sk_user,
        people.contract_role
    FROM
        people
    WHERE
        people.sk_user <> -1
    UNION ALL
    SELECT 
        people.sk_contract,
        people.sk_contract_person,
        cci.id_user AS sk_user,
        people.contract_role
    FROM 
        people
    LEFT JOIN
        datalake_ebdb_customer_contact_identification.customer_contact_identification AS cci
            ON cci.cpf = people.personal_document
            AND cci.id_user IS NOT NULL
    WHERE
        people.sk_user = -1
    UNION ALL
    SELECT 
        people.sk_contract,
        people.sk_contract_person,
        cci.id_user AS sk_user,
        people.contract_role
    FROM 
        people
    LEFT JOIN
        datalake_ebdb_customer_contact_identification.customer_contact_identification AS cci
            ON cci.customer_contact = people.email
            AND cci.id_user IS NOT NULL
    WHERE
        people.sk_user = -1
    UNION ALL
    SELECT 
        people.sk_contract,
        people.sk_contract_person,
        cci.id_user AS sk_user,
        people.contract_role
    FROM 
        people
    LEFT JOIN
        datalake_ebdb_customer_contact_identification.customer_contact_identification AS cci
            ON cci.customer_contact = people.phone_number
            AND cci.id_user IS NOT NULL
    WHERE
        people.sk_user = -1   
),
landlords AS (
    SELECT DISTINCT 
        clientes.sk_contract, 
        clientes.sk_user,  
        DATE(ct.ts_created) AS dt_reference,
        'offboarding_landlord' AS model_name,
        'nps_reversion_off_landlord_rf_v0' AS model_version,
        dc.ts_created AS ts_tickets_search_range_min,
        ct.ts_created AS ts_tickets_search_range_max
    FROM 
        datalake_offboarding.contract_termination AS ct
    LEFT JOIN
        contract_people_togather AS clientes
            ON clientes.sk_contract = ct.id_contract
    LEFT JOIN
        dw_public.dim_contract AS dc
            ON dc.sk_contract = clientes.sk_contract
    WHERE
        clientes.contract_role = 'landlord'
        AND DATE(ct.ts_created) = DATE('{year}-{month}-{day}')
        AND ct.status <> 'CANCELED'
        AND sk_user IS NOT NULL
)
SELECT DISTINCT 
    sk_contract,
    sk_user,
    model_name,
    model_version,
    dt_reference,
    ts_tickets_search_range_max,
    ts_tickets_search_range_min
FROM 
    tenants_adjusted
UNION ALL 
SELECT DISTINCT 
    sk_contract,
    sk_user,
    model_name,
    model_version,
    dt_reference,
    ts_tickets_search_range_max,
    ts_tickets_search_range_min
FROM 
    landlords

