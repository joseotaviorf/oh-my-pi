WITH
lead_ AS (
    SELECT
        dd.date,
        dd.sk_date,
        dr.city_group,
        ac.affiliate_volumetry,
        lf.mkt_origin AS supply_mkt_origin,
        lf.mkt_source AS supply_mkt_source,
        lf.mkt_channel AS supply_mkt_channel,
        lf.mkt_medium AS supply_mkt_medium,
        lf.mkt_completion AS supply_mkt_completion,
        lf.rental_administrator,
        sales_company,
        sourcing_ops,
        context_lead AS context,
        origin_table,
        lead_origin,
        funnel_drop_reason,
        hp.partner AS supply_3p_partner,
        CASE
            WHEN hp.id_house IS NOT NULL THEN 1
            ELSE 0
        END AS is_3p_supply,
        rbh.partner AS supply_3pbh_partner,
        CASE
            WHEN rbh.id_house IS NOT NULL THEN 1
            ELSE 0
        END AS is_3pbh_supply,
        COUNT(lf.sk_lead_date) AS leads,
        CAST(NULL AS BIGINT) AS prospects,
        CAST(NULL AS BIGINT) AS qualifieds,
        CAST(NULL AS BIGINT) AS available_qualifieds,
        CAST(NULL AS BIGINT) AS opportunities,
        CAST(NULL AS BIGINT) AS first_listings,
        lf.country_code
    FROM
        dw_public.dim_date dd
    JOIN
        dw_datamarts.lead_listing_flows lf
            ON dd.sk_date = lf.sk_lead_date
            AND lf.sk_lead_date > 0
    LEFT JOIN
        dw_public.dim_region dr
            ON dr.sk_region = lf.sk_region
    LEFT JOIN
        dw_datamarts.affiliates_clusters ac
            ON ac.sk_user = lf.sk_user_lead_affiliate
            AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(lf.sk_lead_date AS STRING),'yyyyMMdd')))
    LEFT JOIN
        datalake_3p.houses_3p AS hp
            ON hp.id_house = lf.sk_house_listing / 1000
    LEFT JOIN
        datalake_3p.houses_3p_bh AS rbh
            ON rbh.id_house = lf.sk_house_listing / 1000
    WHERE
        dd.date BETWEEN (DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year') AND CURRENT_DATE -- filter data from 4 years ago
    GROUP BY
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 27
),
prospect AS (
    SELECT
        dd.date,
        dd.sk_date,
        dr.city_group,
        ac.affiliate_volumetry,
        lf.mkt_origin AS supply_mkt_origin,
        lf.mkt_source AS supply_mkt_source,
        lf.mkt_channel AS supply_mkt_channel,
        lf.mkt_medium AS supply_mkt_medium,
        lf.mkt_completion AS supply_mkt_completion,
        lf.rental_administrator,
        sales_company,
        sourcing_ops,
        context_prospect AS context,
        origin_table,
        lead_origin,
        funnel_drop_reason,
        hp.partner AS supply_3p_partner,
        CASE
        WHEN hp.id_house IS NOT NULL THEN 1
        ELSE 0
        END AS is_3p_supply,
        rbh.partner AS supply_3pbh_partner,
        CASE
        WHEN rbh.id_house IS NOT NULL THEN 1
        ELSE 0
        END AS is_3pbh_supply,
        CAST(NULL AS BIGINT) AS leads,
        COUNT(lf.sk_prospect_date) AS prospects, -- this count is done on the prospect date because not all listings come FROM a lead, and maybe one lead brings multiple house listings
        CAST(NULL AS BIGINT) AS qualifieds,
        CAST(NULL AS BIGINT) AS available_qualifieds,
        CAST(NULL AS BIGINT) AS opportunities,
        CAST(NULL AS BIGINT) AS first_listings,
        lf.country_code
    FROM
        dw_public.dim_date dd
    JOIN
        dw_datamarts.lead_listing_flows lf
            ON dd.sk_date = lf.sk_prospect_date
            AND lf.sk_prospect_date > 0
    LEFT JOIN
        dw_public.dim_region dr
            ON dr.sk_region = lf.sk_region
    LEFT JOIN
        dw_datamarts.affiliates_clusters ac
            ON ac.sk_user = lf.sk_user_lead_affiliate
            AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(lf.sk_lead_date AS STRING),'yyyyMMdd')))
    LEFT JOIN
        datalake_3p.houses_3p AS hp
            ON hp.id_house = lf.sk_house_listing / 1000
    LEFT JOIN
        datalake_3p.houses_3p_bh AS rbh
            ON rbh.id_house = lf.sk_house_listing / 1000
    WHERE
        dd.date BETWEEN (DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year') AND CURRENT_DATE-- filter data from 4 years ago
    GROUP BY
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 27
),
qualified AS (
    SELECT
        dd.date,
        dd.sk_date,
        dr.city_group,
        ac.affiliate_volumetry,
        lf.mkt_origin AS supply_mkt_origin,
        lf.mkt_source AS supply_mkt_source,
        lf.mkt_channel AS supply_mkt_channel,
        lf.mkt_medium AS supply_mkt_medium,
        lf.mkt_completion AS supply_mkt_completion,
        lf.rental_administrator,
        sales_company,
        sourcing_ops,
        context_qualified AS context,
        origin_table,
        lead_origin,
        funnel_drop_reason,
        hp.partner AS supply_3p_partner,
        CASE
        WHEN hp.id_house IS NOT NULL THEN 1
        ELSE 0
        END AS is_3p_supply,
        rbh.partner AS supply_3pbh_partner,
        CASE
        WHEN rbh.id_house IS NOT NULL THEN 1
        ELSE 0
        END AS is_3pbh_supply,
        CAST(NULL AS BIGINT) AS leads,
        CAST(NULL AS BIGINT) AS prospects,
        COUNT(lf.sk_qualified_date) AS qualifieds, -- this count is done on the qualified date because not all listings come FROM a lead, and maybe one lead brings multiple house listings
        CAST(NULL AS BIGINT) AS available_qualifieds,
        CAST(NULL AS BIGINT) AS opportunities,
        CAST(NULL AS BIGINT) AS first_listings,
        lf.country_code
    FROM
        dw_public.dim_date dd
    JOIN
        dw_datamarts.lead_listing_flows lf
            ON dd.sk_date = lf.sk_qualified_date
            AND lf.sk_qualified_date > 0
    LEFT JOIN
        dw_public.dim_region dr
            ON dr.sk_region = lf.sk_region
    LEFT JOIN
        dw_datamarts.affiliates_clusters ac
            ON ac.sk_user = lf.sk_user_lead_affiliate
            AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(lf.sk_lead_date AS STRING),'yyyyMMdd')))
    LEFT JOIN
        datalake_3p.houses_3p AS hp
            ON hp.id_house = lf.sk_house_listing / 1000
    LEFT JOIN
        datalake_3p.houses_3p_bh AS rbh
            ON rbh.id_house = lf.sk_house_listing / 1000
    WHERE
        dd.date BETWEEN (DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year') AND CURRENT_DATE -- filter data from 4 years ago
    GROUP BY
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 27
),
available_qualified AS (
    SELECT
        dd.date,
        dd.sk_date,
        dr.city_group,
        ac.affiliate_volumetry,
        lf.mkt_origin AS supply_mkt_origin,
        lf.mkt_source AS supply_mkt_source,
        lf.mkt_channel AS supply_mkt_channel,
        lf.mkt_medium AS supply_mkt_medium,
        lf.mkt_completion AS supply_mkt_completion,
        lf.rental_administrator,
        sales_company,
        sourcing_ops,
        context_available_qualified AS context,
        origin_table,
        lead_origin,
        funnel_drop_reason,
        hp.partner AS supply_3p_partner,
        CASE
        WHEN hp.id_house IS NOT NULL THEN 1
        ELSE 0
        END AS is_3p_supply,
        rbh.partner AS supply_3pbh_partner,
        CASE
        WHEN rbh.id_house IS NOT NULL THEN 1
        ELSE 0
        END AS is_3pbh_supply,
        CAST(NULL AS BIGINT) AS leads,
        CAST(NULL AS BIGINT) AS prospects,
        CAST(NULL AS BIGINT) AS qualifieds,
        COUNT(lf.sk_available_qualified_date) AS available_qualifieds, -- this count is done on the qualified date because not all listings come FROM a lead, and maybe one lead brings multiple house listings
        CAST(NULL AS BIGINT) AS opportunities,
        CAST(NULL AS BIGINT) AS first_listings,
        lf.country_code
    FROM
        dw_public.dim_date dd
    JOIN
        dw_datamarts.lead_listing_flows lf
            ON dd.sk_date = lf.sk_available_qualified_date
            AND lf.sk_available_qualified_date > 0
    LEFT JOIN
        dw_public.dim_region dr
            ON dr.sk_region = lf.sk_region
    LEFT JOIN
        dw_datamarts.affiliates_clusters ac
            ON ac.sk_user = lf.sk_user_lead_affiliate
            AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(lf.sk_lead_date AS STRING),'yyyyMMdd')))
    LEFT JOIN
        datalake_3p.houses_3p AS hp
            ON hp.id_house = lf.sk_house_listing / 1000
    LEFT JOIN
        datalake_3p.houses_3p_bh AS rbh
            ON rbh.id_house = lf.sk_house_listing / 1000
    WHERE
        dd.date BETWEEN (DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year') AND CURRENT_DATE -- filter data from 4 years ago
    GROUP BY
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 27
),
opportunity AS (
    SELECT
        dd.date,
        dd.sk_date,
        dr.city_group,
        ac.affiliate_volumetry,
        lf.mkt_origin AS supply_mkt_origin,
        lf.mkt_source AS supply_mkt_source,
        lf.mkt_channel AS supply_mkt_channel,
        lf.mkt_medium AS supply_mkt_medium,
        lf.mkt_completion AS supply_mkt_completion,
        lf.rental_administrator,
        sales_company,
        sourcing_ops,
        context_opportunity AS context,
        origin_table,
        lead_origin,
        funnel_drop_reason,
        hp.partner AS supply_3p_partner,
        CASE
        WHEN hp.id_house IS NOT NULL THEN 1
        ELSE 0
        END AS is_3p_supply,
        rbh.partner AS supply_3pbh_partner,
        CASE
        WHEN rbh.id_house IS NOT NULL THEN 1
        ELSE 0
        END AS is_3pbh_supply,
        CAST(NULL AS BIGINT) AS leads,
        CAST(NULL AS BIGINT) AS prospects,
        CAST(NULL AS BIGINT) AS qualifieds,
        CAST(NULL AS BIGINT) AS available_qualifieds,
        COUNT(DISTINCT lf.sk_house_listing) AS opportunities,
        CAST(NULL AS BIGINT) AS first_listings,
        lf.country_code
    FROM
        dw_public.dim_date dd
    JOIN
        dw_datamarts.lead_listing_flows lf
            ON dd.sk_date = lf.sk_opportunity_date
            AND lf.sk_opportunity_date > 0
    LEFT JOIN
        dw_public.dim_region dr
            ON dr.sk_region = lf.sk_region
    LEFT JOIN
        dw_datamarts.affiliates_clusters ac
            ON ac.sk_user = lf.sk_user_lead_affiliate
            AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(lf.sk_lead_date AS STRING),'yyyyMMdd')))
    LEFT JOIN
        datalake_3p.houses_3p AS hp
            ON hp.id_house = lf.sk_house_listing / 1000
    LEFT JOIN
        datalake_3p.houses_3p_bh AS rbh
            ON rbh.id_house = lf.sk_house_listing / 1000
    WHERE
        dd.date BETWEEN (DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year') AND CURRENT_DATE -- filter data from 4 years ago
    GROUP BY
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 27
),
listing AS (
    SELECT
        dd.date,
        dd.sk_date,
        dr.city_group,
        ac.affiliate_volumetry,
        lf.mkt_origin AS supply_mkt_origin,
        lf.mkt_source AS supply_mkt_source,
        lf.mkt_channel AS supply_mkt_channel,
        lf.mkt_medium AS supply_mkt_medium,
        lf.mkt_completion AS supply_mkt_completion,
        lf.rental_administrator,
        sales_company,
        sourcing_ops,
        context_first_listing AS context,
        origin_table,
        lead_origin,
        funnel_drop_reason,
        hp.partner AS supply_3p_partner,
        CASE
        WHEN hp.id_house IS NOT NULL THEN 1
        ELSE 0
        END AS is_3p_supply,
        rbh.partner AS supply_3pbh_partner,
        CASE
        WHEN rbh.id_house IS NOT NULL THEN 1
        ELSE 0
        END AS is_3pbh_supply,
        CAST(NULL AS BIGINT) AS leads,
        CAST(NULL AS BIGINT) AS prospects,
        CAST(NULL AS BIGINT) AS qualifieds,
        CAST(NULL AS BIGINT) AS available_qualifieds,
        CAST(NULL AS BIGINT) AS opportunities,
        COUNT(DISTINCT lf.sk_house_listing) AS first_listings,
        lf.country_code
    FROM
        dw_public.dim_date dd
    JOIN
        dw_datamarts.lead_listing_flows lf
            ON dd.sk_date = lf.sk_first_listing_date
            AND lf.sk_first_listing_date > 0
    LEFT JOIN
        dw_public.dim_region dr
            ON dr.sk_region = lf.sk_region
    LEFT JOIN
        dw_datamarts.affiliates_clusters ac
            ON ac.sk_user = lf.sk_user_lead_affiliate
            AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(lf.sk_lead_date AS STRING),'yyyyMMdd')))
    LEFT JOIN
        datalake_3p.houses_3p AS hp
            ON hp.id_house = lf.sk_house_listing / 1000
    LEFT JOIN
        datalake_3p.houses_3p_bh AS rbh
            ON rbh.id_house = lf.sk_house_listing / 1000
    WHERE
        dd.date BETWEEN (DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year') AND CURRENT_DATE -- filter data from 4 years ago
    GROUP BY
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 27
),
union_all AS (
    SELECT * FROM lead_
    UNION ALL
    SELECT * FROM prospect
    UNION ALL
    SELECT * FROM qualified
    UNION ALL
    SELECT * FROM available_qualified
    UNION ALL
    SELECT * FROM opportunity
    UNION ALL
    SELECT * FROM listing
),
union_all_date AS (
    SELECT
        dd.date,
        ua.city_group,
        ua.affiliate_volumetry,
        ua.supply_mkt_origin,
        ua.supply_mkt_source,
        ua.supply_mkt_channel,
        ua.supply_mkt_medium,
        ua.supply_mkt_completion,
        ua.rental_administrator,
        ua.sales_company,
        ua.sourcing_ops,
        ua.context,
        ua.origin_table,
        ua.lead_origin,
        ua.funnel_drop_reason,
        ua.supply_3p_partner,
        ua.is_3p_supply,
        ua.supply_3pbh_partner,
        ua.is_3pbh_supply,
        ua.leads,
        ua.prospects,
        ua.qualifieds,
        ua.available_qualifieds,
        ua.opportunities,
        ua.first_listings,
        ua.country_code
    FROM
        union_all ua
    RIGHT JOIN
        dw_public.dim_date dd
            ON ua.sk_date = dd.sk_date
    WHERE
        dd.date BETWEEN (DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year') AND CURRENT_DATE
)
SELECT
    date,
    country_code,
    city_group,
    affiliate_volumetry,
    supply_mkt_origin,
    CASE
        WHEN supply_mkt_origin = 'Owner PWA' THEN supply_mkt_channel
        WHEN supply_mkt_origin != 'Owner PWA' THEN supply_mkt_origin
    END AS supply_mkt_origin_detailed,
    supply_mkt_source,
    supply_mkt_medium,
    CASE
        WHEN supply_mkt_origin = 'B2B' OR supply_mkt_origin = 'CIQ' THEN supply_mkt_origin
        WHEN supply_mkt_completion = 'Full Self-Service' THEN 'FSS'
        ELSE 'IS'
    END AS lead_context,
    sales_company,
    sourcing_ops,
    CASE
        WHEN sourcing_ops IN ('IS Ext', 'IS Int', 'FSS IS PhotoJob', 'Other') AND supply_mkt_origin NOT IN ('B2B','CIQ') THEN 'IS'
        ELSE sourcing_ops
    END AS lead_processing_operation,
    context,
    origin_table,
    lead_origin,
    rental_administrator,
    funnel_drop_reason,
    supply_3p_partner,
    supply_3pbh_partner,
    is_3p_supply,
    is_3pbh_supply,
    SUM(COALESCE(leads,0)) AS leads,
    SUM(COALESCE(prospects,0)) AS prospects,
    SUM(COALESCE(qualifieds,0)) AS qualifieds,
    SUM(COALESCE(available_qualifieds,0)) AS available_qualifieds,
    SUM(COALESCE(opportunities,0)) AS opportunities,
    SUM(COALESCE(first_listings,0)) AS first_listings,
    current_timestamp AS ts_load
FROM
    union_all_date
GROUP BY
    1, 3, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21
