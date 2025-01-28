WITH cte_demand AS (
    WITH agents_3p AS (
        SELECT
            ac.id_agent,
            ac.ts_work_contract_started,
            ac.ts_work_contract_ended,
            NULLIF(wc.`3p_partner`, '') AS demand_3p_partner,
            wc.is_3p_contract
        FROM
            datalake_ebdb_agents.agent_contract AS ac
            JOIN datalake_ebdb_work_contract.work_contract AS wc ON ac.id_work_contract = wc.id
        WHERE
            is_3p_contract
    ),
    demand_3p AS (
        SELECT
            DISTINCT db.sk_booking,
            ap.demand_3p_partner,
            ap.is_3p_contract AS is_3p_demand
        FROM
            agents_3p AS ap
            JOIN dw_public.dim_booking AS db ON ap.id_agent = db.id_agent
            AND db.dt_created BETWEEN ap.ts_work_contract_started
            AND COALESCE(ts_work_contract_ended, db.ts_load)
    )
    SELECT
        fo.sk_offer,
        COALESCE(dp.is_3p_demand, False) AS is_3p_demand
    FROM
        dw_sale.fact_offers AS fo
        LEFT JOIN demand_3p AS dp ON fo.sk_booking = dp.sk_booking
        LEFT JOIN datalake_gsheets_clean.forbrokers_3p_partner_conditions pc ON UPPER(dp.demand_3p_partner) = UPPER(pc.partner_short_name)
    WHERE
        TRIM(is_3p_demand) = 'true'
),
cte_categoria AS (
    SELECT
        fo.sk_offer,
        CASE
            WHEN da.is_3p_demand = 'true'
            AND da.is_3p_supply = 'true' THEN '6P'
            WHEN da.is_3p_demand = 'true' THEN '3P - Demand'
            WHEN da.is_3p_supply = 'true' THEN '3P - Supply'
        END AS tipo
    FROM
        dw_sale.fact_offers fo
        LEFT JOIN dw_sale.dim_sale_agreement da ON da.sk_offer = fo.sk_offer
),
cte_categoria_filtro AS (
    SELECT
        cc.sk_offer,
        CASE
            WHEN demand.is_3p_demand THEN '3P - Demand'
            WHEN cc.tipo IS NOT NULL THEN cc.tipo
            ELSE NULL
        END AS partner_types
    FROM
        cte_categoria cc
        LEFT JOIN cte_demand demand ON demand.sk_offer = cc.sk_offer
)
SELECT
    fo.sk_offer AS external_id,
    fo.sk_house AS house_id,
    CASE
        WHEN dof.business_unit LIKE '%[3P%' AND dr.city_group IN ('Rio de Janeiro') THEN '22'
        WHEN dof.business_unit LIKE '%[3P%' AND dr.city_group
        IN (
            'RMSP',
            'Ribeirão Preto',
            'Santos',
            'Sorocaba',
            'São José do Rio Preto',
            'São José dos Campos'
        ) THEN '2'
        ELSE fo.sk_business_unit
    END AS business_unit_id,
    cc.partner_types AS category,
    dh.address AS house_address,
    dh.city AS house_city,
    dh.complement AS house_complement,
    dh.neighborhood AS house_neighborhood,
    dh.number AS house_number,
    dh.zipcode AS house_zipcode,
    ds.sale_price_agreed AS price_agreed,
    ds.brokerage_fee AS brokerage,
    ds.sale_agreement_cancellation_reason AS cancellation_reason,
    ds.ts_sale_agreement_cancelled AS cancellation_date,
    TO_DATE(STRING(fc.sk_payment_allowed_date), 'yyyyMMdd') AS payment_allowed_date,
    ds.ts_sale_agreement_signed AS signature_date,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    dw_sale.dim_offer dof
LEFT JOIN
    dw_sale.fact_offers fo
        ON fo.sk_offer = dof.sk_offer
LEFT JOIN
    dw_sale.fact_closing_flows fc
        ON fc.sk_offer = dof.sk_offer
LEFT JOIN
    dw_house.dim_house dh
        ON fo.sk_house = dh.sk_house
LEFT JOIN
    dw_sale.dim_sale_agreement ds
        ON ds.sk_offer = dof.sk_offer
LEFT JOIN
    cte_categoria_filtro cc
        ON cc.sk_offer = dof.sk_offer
LEFT JOIN
    dw_public.dim_region dr
        ON dr.sk_region = fo.sk_region
WHERE
    ds.ts_sale_agreement_signed IS NOT NULL
