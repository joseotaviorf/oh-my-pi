WITH business_contexts_separated_aux AS (
    SELECT
        EXPLODE(ARRAY('SALE', 'RENT', 'Unknown')) AS business_context,
        ARRAY('FIRST_BATCH', 'FIRST_MONTH_BATCH', 'COMPLEMENTARY', 'RECURRENT', 'N/A') AS recurrency_types,
        ARRAY('HUNTING', 'FARMING', 'N/A') AS acquisition_teams
),
recurrency_separated_aux AS (
    SELECT
        business_context,
        EXPLODE(recurrency_types) AS recurrency_type,
        acquisition_teams
    FROM
        business_contexts_separated_aux
),
acquisition_teams_separated_aux AS (
    SELECT
        business_context,
        recurrency_type,
        EXPLODE(acquisition_teams) AS acquisition_team
    FROM
        recurrency_separated_aux
),
integrator_companies AS (
    SELECT DISTINCT
        c.id_company AS id_company_integrator,
        c.trade_name AS integrator_trade_name
    FROM
        datalake_brokers_supply_processor.business_context_detail AS bcd
    JOIN
        datalake_company.company AS c
            ON bcd.id_partner = c.uuid_company
    UNION ALL
    SELECT
        -1 AS id_company_integrator,
        'N/A' AS integrator_trade_name
)
SELECT
    ROW_NUMBER() OVER (
        PARTITION BY 1
        ORDER BY
            id_company_integrator,
            acquisition_team DESC,
            business_context,
            recurrency_type
        ) AS sk_lead_3p_context,
    business_context,
    recurrency_type,
    acquisition_team,
    integrator_trade_name,
    business_context = 'SALE' AS is_for_sale,
    business_context = 'RENT' AS is_for_rent,
    recurrency_type = 'FIRST_BATCH' AS is_first_batch,
    recurrency_type = 'FIRST_MONTH_BATCH' AS is_first_month_batch,
    recurrency_type = 'COMPLEMENTARY' AS is_complementary,
    recurrency_type = 'RECURRENT' AS is_recurrent,
    acquisition_team = 'HUNTING' AS is_hunting,
    acquisition_team = 'FARMING' AS is_farming,
    NOW() AS ts_load
FROM
    acquisition_teams_separated_aux,
    integrator_companies
