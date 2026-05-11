WITH
cte_demand AS (
    WITH agents_3p AS (
        SELECT
            ac.id_agent,
            ac.ts_work_contract_started,
            ac.ts_work_contract_ended,
            NULLIF(wc.`3p_partner`, '') AS demand_3p_partner,
            wc.is_3p_contract
        FROM
            datalake_ebdb_agents.agent_contract AS ac
        JOIN
            datalake_ebdb_work_contract.work_contract AS wc
                ON ac.id_work_contract = wc.id
        WHERE
            is_3p_contract
    ),
    demand_3p AS (
        SELECT DISTINCT
            vs.id_schedule AS sk_booking,
            ap.demand_3p_partner,
            ap.is_3p_contract AS is_3p_demand
        FROM
            agents_3p AS ap
        JOIN
            datalake_visit.visit_schedules AS vs
                ON ap.id_agent = vs.id_agent
                AND vs.ts_schedule_created BETWEEN ap.ts_work_contract_started AND COALESCE(ts_work_contract_ended, vs.ts_load)
    )
    SELECT
        fo.sk_offer,
        COALESCE(dp.is_3p_demand, False) AS is_3p_demand,
        pc.partner_short_name
    FROM
        dw_sale.fact_offers AS fo
    LEFT JOIN
        demand_3p AS dp
            ON fo.sk_booking = dp.sk_booking
    LEFT JOIN
        datalake_gsheets_clean.forbrokers_3p_partner_conditions pc
            ON UPPER(dp.demand_3p_partner) = UPPER(pc.partner_short_name)
    WHERE TRIM(COALESCE(dp.is_3p_demand, False)) = 'true'
),


cte_categoria AS (
    SELECT
        fo.sk_offer,
        CASE
            WHEN da.is_3p_demand = 'true' AND da.is_3p_supply = 'true'  THEN '6P'
            WHEN da.is_3p_demand = 'true' THEN '3P - Demand'
            WHEN da.is_3p_supply = 'true' THEN '3P - Supply'
        END AS tipo,
        CASE
            WHEN da.is_3p_demand = 'true' THEN cd.company_name
        END AS agents_partner,
        CASE
            WHEN da.is_3p_supply = 'true' THEN cs.company_name
        END AS partner
    FROM
        dw_sale.fact_offers fo
    LEFT JOIN
        dw_sale.dim_sale_agreement da
            ON da.sk_offer = fo.sk_offer
    LEFT JOIN
        dw_public.dim_company_3p_partners cd
            ON cd.sk_company = fo.sk_company_demand
    LEFT JOIN
        dw_public.dim_company_3p_partners cs
            ON cs.sk_company = fo.sk_company_supply
),

cte_categoria_filtro AS (
    SELECT
        fo.sk_offer,
        CASE
            WHEN demand.is_3p_demand THEN '3P - Demand'
            WHEN cc.tipo = '3P - Supply' THEN '3P - Supply'
            WHEN cc.tipo = '6P' THEN '6P'
            ELSE 'QuintoAndar'
        END AS partner_types,
            CASE WHEN cc.tipo IS NOT NULL THEN 'ForBrokers'
            ELSE 'QuintoAndar'
        END AS service_line,
        cc.partner,
        cc.agents_partner
    FROM
        dw_sale.fact_offers fo
    LEFT JOIN
        cte_categoria cc
            ON cc.sk_offer = fo.sk_offer
    LEFT JOIN
        cte_demand demand
            ON demand.sk_offer = fo.sk_offer

),

cte_partner_demand AS (
        SELECT
            dim.sk_offer AS offer_id,
            'Imobiliária - demand' AS `role`,
            demand.partner_short_name AS partner_id
    FROM
        dw_sale.dim_offer dim
    LEFT JOIN
        cte_categoria_filtro cc
            ON cc.sk_offer = dim.sk_offer
    LEFT JOIN
        cte_demand demand
            ON demand.sk_offer = dim.sk_offer
            AND UPPER(demand.partner_short_name) = UPPER(cc.agents_partner)
    WHERE
        NULLIF(TRIM(demand.partner_short_name), '') IS NOT NULL

),

cte_partner_supply AS (
        SELECT
            dim.sk_offer AS offer_id,
            'Imobiliária - supply' AS `role`,
            pc_s.partner_short_name AS partner_id

    FROM
        dw_sale.dim_offer dim
    LEFT JOIN
        cte_categoria_filtro cc
            ON cc.sk_offer = dim.sk_offer
    LEFT JOIN
        datalake_gsheets_clean.forbrokers_3p_partner_conditions AS pc_s
            ON pc_s.partner_short_name = cc.partner
    WHERE
        NULLIF(TRIM(pc_s.partner), '') IS NOT NULL
)

SELECT
    dim.sk_offer AS offer_id,
    dc.uuid_company,
    CASE
        WHEN demand.partner_short_name IS NOT NULL THEN demand.partner_short_name
        WHEN pc_s.partner_short_name IS NOT NULL THEN pc_s.partner_short_name
        ELSE NULL
    END AS partner_id,
    CASE
        WHEN demand.partner_short_name IS NOT NULL THEN 'Imobiliária - demand'
        WHEN pc_s.partner_short_name IS NOT NULL THEN 'Imobiliária - supply'
        ELSE NULL
    END AS `role`,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    dw_sale.dim_offer dim
LEFT JOIN
    cte_categoria_filtro cc
        ON cc.sk_offer = dim.sk_offer
LEFT JOIN
    cte_demand demand
        ON demand.sk_offer = dim.sk_offer
        AND UPPER(demand.partner_short_name) = UPPER(cc.agents_partner)
LEFT JOIN
    datalake_gsheets_clean.forbrokers_3p_partner_conditions pc_s
        ON UPPER(pc_s.partner_short_name) = UPPER(cc.partner)
LEFT JOIN
    dw_public.dim_company_3p_partners AS dc
        ON pc_s.partner_short_name = dc.hubspot_company_tag
        AND dc.hubspot_status != 'Archived'
        AND dc.uuid_company IS NOT NULL
WHERE
    demand.partner_short_name IS NOT NULL
    OR pc_s.partner_short_name IS NOT NULL
