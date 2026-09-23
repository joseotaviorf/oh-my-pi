WITH obt_with_flag AS (
    SELECT
        CAST(obt.sk_house AS BIGINT) AS sk_house,
        CAST(obt.date AS DATE) AS date,
        CAST(obt.week_start AS DATE) AS week_start,
        CAST(obt.month_start AS DATE) AS month_start,
        CAST(obt.sk_region AS BIGINT) AS sk_region,
        UPPER(obt.planning_conversion) AS planning_conversion,
        CAST(fact_lead_3p.sk_broker AS BIGINT) AS sk_broker,
        CASE
            WHEN CAST(obt.date AS DATE) BETWEEN DATE '2025-09-01' AND DATE '2025-11-18'
            AND obt.nm_business_context = 'RENT'
            AND CAST(obt.sk_user_conversion AS BIGINT) IN (8919771,11299701,6001450) THEN TRUE
            WHEN CAST(obt.date AS DATE) BETWEEN DATE '2025-09-01' AND DATE '2025-11-18'
            AND obt.nm_business_context = 'RENT'
            AND CAST(obt.sk_user_affiliate AS BIGINT) IN (12306405,14046860,14053116,14046994,14217303,14294994) THEN TRUE
            WHEN CAST(obt.date AS DATE) >= DATE '2025-09-01'
            AND obt.nm_business_context = 'RENT'
            AND LOWER(obt.nm_agent) IN ('ciq_pj','3p_fr') THEN TRUE
            WHEN UPPER(obt.planning_conversion) = 'REDE' THEN TRUE
            ELSE FALSE
        END AS is_3p_fr_test,
        CASE
            WHEN CAST(obt.date AS DATE) BETWEEN DATE '2025-09-01' AND DATE '2025-11-18'
            AND obt.nm_business_context = 'RENT'
            AND CAST(obt.sk_user_conversion AS BIGINT) IN (8919771,11299701,6001450) THEN TRUE
            WHEN CAST(obt.date AS DATE) BETWEEN DATE '2025-09-01' AND DATE '2025-11-18'
            AND obt.nm_business_context = 'RENT'
            AND CAST(obt.sk_user_affiliate AS BIGINT) IN (12306405,14046860,14053116,14046994,14217303,14294994) THEN TRUE
            WHEN CAST(obt.date AS DATE) >= DATE '2025-09-01'
            AND obt.nm_business_context = 'RENT'
            AND LOWER(obt.nm_agent) IN ('ciq_pj','3p_fr') THEN TRUE
            ELSE FALSE
        END AS is_ops,
        CASE
            WHEN UPPER(obt.planning_conversion) = 'REDE'
            AND fact_lead_3p.sk_lead_3p IS NULL THEN TRUE
            WHEN UPPER(obt.planning_conversion) = 'REDE'
            AND fact_lead_3p.sk_lead_3p IS NOT NULL
            AND CAST(DATE_TRUNC('DAY', fact_lead_3p.ts_first_listing) AS DATE) < DATE '2026-02-19' THEN TRUE
            ELSE FALSE
        END AS is_organic,
        CASE
            WHEN UPPER(obt.planning_conversion) = 'REDE'
            AND fact_lead_3p.sk_lead_3p IS NOT NULL
            AND CAST(DATE_TRUNC('DAY', fact_lead_3p.ts_first_listing) AS DATE) >= DATE '2026-02-19' THEN TRUE
            ELSE FALSE
        END AS is_bsp
    FROM dw_growth.obt_supply obt
    LEFT JOIN dw_3p_supply.fact_lead_3p_flows fact_lead_3p
    ON CAST(obt.sk_house AS BIGINT) = CAST(fact_lead_3p.sk_house AS BIGINT)
    AND fact_lead_3p.business_context = 'RENT'
    AND fact_lead_3p.ts_first_listing IS NOT NULL
    WHERE obt.nm_business_context = 'RENT'
    AND obt.cd_funnel_step = 'first_listing'
    AND CAST(obt.month_start AS DATE) >= DATE('2025-09-01')
),
bsp_sale AS (
    SELECT
        CAST(sk_house AS BIGINT) AS sk_house,
        sk_broker,
        ROW_NUMBER() OVER(PARTITION BY sk_house ORDER BY sk_lead_3p DESC) AS rn
    FROM dw_3p_supply.fact_lead_3p_flows
    WHERE business_context = 'SALE'
    AND sk_house IS NOT NULL
    AND sk_house <> -1
),
obt_supply_filtered AS (
    SELECT
        o.sk_house,
        o.date,
        o.week_start,
        o.month_start,
        CASE
            WHEN LOWER(TRIM(COALESCE(dr.city_group,''))) IN (
                'rmsp','são paulo','sao paulo','santo andré','santo andre',
                'são bernardo do campo','sao bernardo do campo','são caetano do sul','sao caetano do sul',
                'diadema','mauá','maua','ribeirão pires','ribeirao pires','rio grande da serra',
                'arujá','aruja','biritiba mirim','ferraz de vasconcelos','guararema',
                'itaquaquecetuba','mogi das cruzes','poá','poa','salesópolis','salesopolis',
                'santa isabel','suzano','barueri','carapicuíba','carapicuiba','cotia',
                'embu das artes','itapevi','jandira','osasco','pirapora do bom jesus',
                'santana de parnaíba','santana de parnaiba','vargem grande paulista','caieiras',
                'cajamar','francisco morato','franco da rocha','mairiporã','mairipora',
                'embu-guaçu','embu guacu','itapecerica da serra','juquitiba',
                'são lourenço da serra','sao lourenco da serra','taboão da serra','taboao da serra',
                'guarulhos','santos','sorocaba','são josé dos campos','sao jose dos campos',
                'jundiaí','jundiai','guarúja','guaruja','praia grande','taubaté','taubate'
            ) THEN 'RMSP'
            WHEN LOWER(TRIM(COALESCE(dr.city_group,''))) IN (
                'rio de janeiro','belo horizonte','curitiba','campinas','Campinas','porto alegre',
                'goiânia','goiania','brasília','brasilia'
            ) THEN dr.city_group
            ELSE 'Other cities'
        END AS specific_city_group,
        CASE
            WHEN LOWER(TRIM(COALESCE(dr.city_group, ''))) IN (
                'rmsp', 'são paulo', 'sao paulo', 'santo andré', 'santo andre',
                'são bernardo do campo', 'sao bernardo do campo', 'são caetano do sul', 'sao caetano do sul',
                'diadema', 'mauá', 'maua', 'ribeirão pires', 'ribeirao pires', 'rio grande da serra',
                'arujá', 'aruja', 'biritiba mirim', 'ferraz de vasconcelos', 'guararema',
                'itaquaquecetuba', 'mogi das cruzes', 'poá', 'poa', 'salesópolis', 'salesopolis',
                'santa isabel', 'suzano', 'barueri', 'carapicuíba', 'carapicuiba', 'cotia',
                'embu das artes', 'itapevi', 'jandira', 'osasco', 'pirapora do bom jesus',
                'santana de parnaíba', 'santana de parnaiba', 'vargem grande paulista', 'caieiras',
                'cajamar', 'francisco morato', 'franco da rocha', 'mairiporã', 'mairipora',
                'embu-guaçu', 'embu guacu', 'itapecerica da serra', 'juquitiba',
                'são lourenço da serra', 'sao lourenco da serra', 'taboão da serra', 'taboao da serra',
                'guarulhos', 'santos', 'sorocaba', 'são josé dos campos', 'sao jose dos campos',
                'jundiaí', 'jundiai', 'guarúja', 'guaruja', 'praia grande', 'taubaté', 'taubate'
            ) THEN 'RMSP'
            ELSE 'CGRM'
        END AS city_group,
        o.is_3p_fr_test,
        o.is_ops,
        o.is_organic,
        o.is_bsp,
        o.planning_conversion,
        CASE
            WHEN o.is_3p_fr_test = TRUE
            THEN COALESCE(dc.broker_name, dc_sale.broker_name, 'Imobiliária Não Encontrada')
            ELSE 'Imobiliária Não Encontrada'
        END AS hubspot_company_tag,
        
        -- NOVA COLUNA: Criada mantendo o mesmo comportamento da hubspot_company_tag
        CASE
            WHEN o.is_3p_fr_test = TRUE
            THEN COALESCE(dc.broker_trade_name_tag, dc_sale.broker_trade_name_tag, 'Imobiliária Não Encontrada')
            ELSE 'Imobiliária Não Encontrada'
        END AS broker_trade_name_tag,

        CAST(dhl.sk_house_listing AS BIGINT) AS sk_house_listing,
        dhl.house_status AS status
    FROM obt_with_flag o
    LEFT JOIN dw_brokers.dim_broker dc
    ON CAST(o.sk_broker AS BIGINT) = CAST(dc.sk_broker AS BIGINT)
    LEFT JOIN dw_public.dim_region dr
    ON CAST(o.sk_region AS BIGINT) = CAST(dr.sk_region AS BIGINT)
    LEFT JOIN dw_rent.dim_house_listing dhl
    ON CAST(o.sk_house AS BIGINT) = CAST(dhl.id_house AS BIGINT)
    AND CAST(dhl.version AS BIGINT) = 1
    LEFT JOIN bsp_sale bs
    ON o.sk_house = bs.sk_house AND bs.rn = 1
    LEFT JOIN dw_brokers.dim_broker dc_sale
    ON CAST(bs.sk_broker AS BIGINT) = CAST(dc_sale.sk_broker AS BIGINT)
),
marco_zero AS (
    SELECT
        hubspot_company_tag,
        MIN(date) AS first_batch_start
    FROM obt_supply_filtered
    WHERE hubspot_company_tag NOT IN ('Imobiliária Não Encontrada')
    GROUP BY 1
),
supply_with_batch AS (
    SELECT
        o.*,
        CASE
            WHEN o.date <= date_add(mz.first_batch_start, 30) THEN 'First Batch'
            ELSE 'Recurrence'
        END AS tipo_envio
    FROM obt_supply_filtered o
    LEFT JOIN marco_zero mz
    ON o.hubspot_company_tag = mz.hubspot_company_tag
),
build_r_1w AS (
    SELECT
        CAST(fde.sk_house_listing AS BIGINT) AS sk_house_listing,
        fde.sk_event,
        CASE
            WHEN CAST(dt.date AS DATE) >= CAST(dhl.ts_publication AS DATE)
            AND CAST(dt.date AS DATE) <= date_add(CAST(dhl.ts_publication AS DATE), 7)
            THEN TRUE
            ELSE FALSE
        END AS contract_signed_7d
    FROM dw_rent.fact_rent_demand_events fde
    LEFT JOIN dw_public.dim_date dt
    ON CAST(dt.sk_date AS BIGINT) = CAST(fde.sk_event_date AS BIGINT)
    LEFT JOIN dw_rent.dim_house_listing dhl
    ON CAST(fde.sk_house_listing AS BIGINT) = CAST(dhl.sk_house_listing AS BIGINT)
    WHERE CAST(fde.sk_event_type AS BIGINT) = 9
    AND CAST(dt.date AS DATE) >= DATE('2025-09-01')
),
r_1w AS (
    SELECT
        sk_house_listing,
        COUNT(DISTINCT sk_event) AS contract_signed
    FROM build_r_1w
    WHERE contract_signed_7d = TRUE
    GROUP BY sk_house_listing
),
build_hdi3 AS (
    SELECT
        CAST(hdi3.id_house_listing AS BIGINT) AS id_house_listing,
        hdi3.status_history,
        hdi3.status_change_reason,
        CAST(hdi3.dt_day AS DATE) AS dt_day
    FROM datalake_rental_historical_follow_up.house_listings_daily_info hdi3
    WHERE CAST(hdi3.dt_day AS DATE) >= DATE('2025-09-01')
    AND hdi3.is_rent_3p_supply = TRUE
),
status AS (
    SELECT DISTINCT
        CAST(dhl.sk_house_listing AS BIGINT) AS sk_house_listing,
        CASE
            WHEN COALESCE(hdi3.status_history, dhl.house_status) IN ('SUSPENDED','suspenso')
            AND COALESCE(hdi3.status_change_reason, dhl.house_rent_status) IN ('RENTED') THEN 'alugado'
            WHEN COALESCE(hdi3.status_history, dhl.house_status) IN ('PUBLISHED','publicado') THEN 'publicado'
            WHEN COALESCE(hdi3.status_history, dhl.house_status) IN ('SUSPENDED','suspenso') THEN 'suspenso'
            WHEN COALESCE(hdi3.status_history, dhl.house_status) IN ('edicao','EDITING') THEN 'edicao'
            WHEN COALESCE(hdi3.status_history, dhl.house_status) IN ('excluido','OPTED_OUT') THEN 'excluido'
            WHEN COALESCE(hdi3.status_history, dhl.house_status) IN ('despublicado','UNPUBLISHED') THEN 'despublicado'
            WHEN COALESCE(hdi3.status_history, dhl.house_status) IS NULL THEN 'nao_relistado'
            ELSE COALESCE(hdi3.status_history, dhl.house_status)
        END AS status_1w,
        CASE
            WHEN dtsusp.ts_suspension_end IS NOT NULL THEN 'Com_Data_Volta'
            WHEN hdi3.status_history IN ('SUSPENDED','suspenso')
            AND hdi3.status_change_reason IN ('HouseReserved','ContractDraft','PaidGuarantee') THEN 'Reserva/Minuta'
            WHEN hdi3.status_history IN ('despublicado','UNPUBLISHED')
            AND hdi3.status_change_reason IN ('MULTIPLE_LISTING_OF_THE_SAME_OWNER') THEN 'Duplicados_PPM'
            ELSE 'Outros'
        END AS status_reason_1w
    FROM dw_rent.dim_house_listing dhl
    LEFT JOIN build_hdi3 hdi3
    ON CAST(hdi3.id_house_listing AS BIGINT) = CAST(dhl.sk_house_listing AS BIGINT)
    AND CAST(hdi3.dt_day AS DATE) = date_add(CAST(dhl.ts_listing_version_start AS DATE), 7)
    LEFT JOIN datalake_ebdb_listing.house dtsusp
    ON CAST(dhl.id_house AS BIGINT) = CAST(dtsusp.id AS BIGINT)
    WHERE CAST(dhl.ts_listing_version_start AS DATE) >= DATE('2025-09-01')
),
first_listing AS (
    SELECT
        COUNT(DISTINCT o.sk_house) AS count_first_listing,
        SUM(qs.price_score_pub) AS sum_price_score_pub,
        SUM(qs.easy_entry_pub) AS sum_easy_entry_pub,
        CASE
            WHEN CAST(o.month_start AS DATE) >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL 3 MONTH
            THEN o.date
            ELSE o.week_start
        END AS gran_day_or_week,
        o.month_start,
        o.hubspot_company_tag,
        o.broker_trade_name_tag,
        o.is_3p_fr_test,
        o.specific_city_group,
        o.city_group,
        o.planning_conversion,
        CASE
            WHEN bd.status_1w IN ('suspenso') AND bd.status_reason_1w IN ('Reserva/Minuta') THEN 'negociacao_avancada'
            WHEN bd.status_reason_1w IN ('Com_Data_Volta') THEN 'data_para_voltar'
            WHEN bd.status_1w IN ('despublicado') AND bd.status_reason_1w IN ('Duplicados_PPM') THEN 'duplicados_PPM'
            WHEN bd.status_1w IN ('publicado') THEN 'publicado'
            WHEN bd.status_1w IN ('alugado') OR COALESCE(r_1w.contract_signed, 0) > 0 THEN 'alugado'
            ELSE 'suspenso_despublicado'
        END AS status_1w,
        qs.time_completed_1w,
        o.is_ops,
        o.is_organic,
        o.is_bsp,
        o.tipo_envio
    FROM supply_with_batch o
    LEFT JOIN sandbox.listing_scores qs
    ON CAST(qs.sk_house_listing AS BIGINT) = CAST(o.sk_house_listing AS BIGINT)
    LEFT JOIN status bd
    ON CAST(bd.sk_house_listing AS BIGINT) = CAST(o.sk_house_listing AS BIGINT)
    LEFT JOIN r_1w
    ON CAST(r_1w.sk_house_listing AS BIGINT) = CAST(o.sk_house_listing AS BIGINT)
    GROUP BY
        CASE
            WHEN CAST(o.month_start AS DATE) >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL 3 MONTH
            THEN o.date
            ELSE o.week_start
        END,
        o.month_start,
        o.hubspot_company_tag,
        o.broker_trade_name_tag, -- NOVA COLUNA adicionada ao GROUP BY
        o.is_3p_fr_test,
        o.specific_city_group,
        o.city_group,
        o.planning_conversion,
        CASE
            WHEN bd.status_1w IN ('suspenso') AND bd.status_reason_1w IN ('Reserva/Minuta') THEN 'negociacao_avancada'
            WHEN bd.status_reason_1w IN ('Com_Data_Volta') THEN 'data_para_voltar'
            WHEN bd.status_1w IN ('despublicado') AND bd.status_reason_1w IN ('Duplicados_PPM') THEN 'duplicados_PPM'
            WHEN bd.status_1w IN ('publicado') THEN 'publicado'
            WHEN bd.status_1w IN ('alugado') OR COALESCE(r_1w.contract_signed, 0) > 0 THEN 'alugado'
            ELSE 'suspenso_despublicado'
        END,
        qs.time_completed_1w,
        o.is_ops,
        o.is_organic,
        o.is_bsp,
        o.tipo_envio
)
SELECT
    count_first_listing,
    gran_day_or_week,
    month_start,
    hubspot_company_tag,
    is_3p_fr_test,
    specific_city_group,
    city_group,
    planning_conversion,
    status_1w,
    time_completed_1w,
    sum_price_score_pub,
    sum_easy_entry_pub,
    is_ops,
    is_organic,
    is_bsp,
    tipo_envio,
    broker_trade_name_tag
FROM first_listing
ORDER BY gran_day_or_week DESC
