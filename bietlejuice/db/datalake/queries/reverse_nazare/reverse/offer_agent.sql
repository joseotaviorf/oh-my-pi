WITH cte_agents_visit AS (
    SELECT
        sk_sale_flow,
        dw.sk_user::INT AS sk_agent,
        sk_agent::INT AS sk_user_agent,
        max(sk_visit_completed_date) AS sk_visit_completed_date
    FROM
        dw_sale.fact_visits fv
    LEFT JOIN
        dw_public.dim_user dw
            ON dw.dados_agente_id = fv.sk_agent
    WHERE sk_visit_completed_date > 0
    GROUP BY 1,2,3
),
cte_executivo_visitas AS (
    SELECT
        fo.sk_offer,
        du.sk_user::INT AS sk_user_rh,
        'Executivo Visitas' AS partner_type
    FROM
        dw_sale.fact_offers fo
    LEFT JOIN
        dw_public.dim_user du
            ON du.sk_user = fo.sk_user_agent
    LEFT JOIN
        cte_agents_visit av
            ON av.sk_user_agent = du.sk_user
            AND av.sk_sale_flow = fo.sk_sale_flow
),
cte_fifity_name AS (
    SELECT
        fo.sk_offer,
        du.sk_user::INT AS sk_user_rh,
        'Executivo Visitas Fifty' AS partner_type
    FROM
        cte_agents_visit av
    LEFT JOIN
        dw_public.dim_user du
            ON av.sk_user_agent = du.sk_user
    LEFT JOIN
        dw_sale.fact_offers fo
            ON av.sk_sale_flow = fo.sk_sale_flow
            AND du.sk_user <> fo.sk_user_agent
    WHERE
        fo.sk_offer IS NOT NULL
),
cte_executivo_associado AS (
    SELECT DISTINCT
        dim.sk_offer,
        du.sk_user AS sk_user_rh,
        'Executivo Associado' AS partner_type
    FROM
        dw_sale.dim_offer dim
    LEFT JOIN
        dw_sale.fact_offers fo
            ON fo.sk_offer = dim.sk_offer
    LEFT JOIN
        dw_sale.dim_sale_agreement sa
            ON dim.sk_offer = sa.sk_offer
    LEFT JOIN
        dw_public.dim_user du
            ON du.sk_user = fo.sk_user_team_lead
    WHERE
        team_lead_name IS NOT NULL
),
cte_executivo_negociacao AS (
    SELECT DISTINCT
        dim.sk_offer,
        du.sk_user::INT AS sk_user_rh,
        'Executivo Negociacao' AS partner_type
    FROM
        dw_sale.dim_offer dim
    LEFT JOIN
        dw_sale.fact_offers fo
            ON fo.sk_offer = dim.sk_offer
    LEFT JOIN
        dw_sale.dim_sale_agreement sa
            ON sa.sk_offer = dim.sk_offer
    LEFT JOIN
        dw_public.dim_user du
            ON du.sk_user = fo.sk_user_consultant
    WHERE
        deal_maker_name IS NOT NULL
),
cte_final AS (
    SELECT * FROM cte_executivo_visitas
    UNION ALL
    SELECT * FROM cte_executivo_associado
    UNION ALL
    SELECT * FROM cte_executivo_negociacao
    UNION ALL
    SELECT * FROM cte_fifity_name
)

SELECT *,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    cte_final
