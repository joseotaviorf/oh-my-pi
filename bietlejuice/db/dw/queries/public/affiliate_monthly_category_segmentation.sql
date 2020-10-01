WITH date_month_range as (
    SELECT
        DISTINCT
        sk_date,
        month_start,
        month_end
    FROM dim_date d
    WHERE  d.month_start = d.date
        AND d.date BETWEEN add_months('{0}'::DATE, -17) AND add_months('{0}'::DATE, 1)
)
,base_aff as (
    SELECT
        duaf.sk_user_affiliate,
        u.dados_afiliado_id,
        duaf.type AS affiliate_type,
        u.sk_user,
        date(duaf.ts_joined_program) AS sign_up_date,
        dt.month_start,
        dt.sk_date,
        dt.month_end,
        datediff(day,date(ts_joined_program),dt.month_start) AS lifetime_days_cohort,
        CAST(
            COUNT(
                DISTINCT CASE WHEN fhl.sk_lead_date > 0 AND dt_lead.date < dt.month_start THEN fhl.sk_house_listing_flow END
            )
            AS FLOAT
        ) AS "leads",
        CAST(
            COUNT(
                DISTINCT CASE WHEN fhl.sk_prospect_date > 0 AND dt_prospect.date < dt.month_start then fhl.sk_house_listing_flow END
            )
            AS FLOAT
        ) AS "prospects",
        CAST(
            COUNT(
                DISTINCT CASE WHEN fhl.sk_prospect_date > 0 AND dt_prospect.date BETWEEN date(add_months(dt.month_start,-3))
                AND add_months(dt.month_end,-1) THEN fhl.sk_house_listing_flow END
            )
            AS FLOAT)
        AS "prospects_last_90_days",
        CAST(
            COUNT(
                DISTINCT CASE WHEN fhl.sk_prospect_date > 0 AND dt_prospect.date BETWEEN date(add_months(dt.month_start,-3))
                AND date(add_months(dt.month_end,-1)) THEN dt_prospect.month END
            )
            AS FLOAT)
        AS "active_last_90_days_in_months",
        CAST(
            COUNT(
                DISTINCT CASE WHEN fhl.sk_first_listing_date > 0 AND dt_listing.date < dt.month_start then fhl.sk_house_listing_flow END
            )
            AS FLOAT)
        AS "listings",
        CAST(
            COUNT(
                DISTINCT CASE WHEN fhl.sk_first_listing_date > 0 AND dt_listing.date BETWEEN date(add_months(dt.month_start,-3))
                AND add_months(dt.month_end,-1) then fhl.sk_house_listing_flow END
            )
            AS FLOAT)
        AS "listings_last_90_days",
        RANK() OVER(PARTITION BY duaf.sk_user_affiliate ORDER BY dt.month_start DESC) = 1 as is_last_segmentation
    FROM dim_user_affiliate duaf
    CROSS JOIN date_month_range dt
    JOIN dim_user u
        ON u.dados_afiliado_id = duaf.sk_user_affiliate
    LEFT JOIN fact_house_listing_flows fhl
        ON fhl.sk_user_lead_affiliate = u.sk_user
    LEFT JOIN dim_date dt_lead
        ON dt_lead.sk_date = fhl.sk_lead_date
    LEFT JOIN dim_date dt_prospect
        ON dt_prospect.sk_date = fhl.sk_prospect_date
    LEFT JOIN dim_date dt_listing
        ON dt_listing.sk_date = fhl.sk_first_listing_date
    WHERE duaf.type IN ('Standard', 'Agent')
    GROUP BY 1,2,3,4,5,6,7,8,9
), ratios AS (
    SELECT
        *,
        baf.listings/coalesce(nullif(baf.leads,0),1) AS conversion_lead_to_listing,
        baf.listings/coalesce(nullif(baf.prospects,0),1) AS conversion_prospect_to_listing,
        baf.prospects_last_90_days/coalesce(nullif(baf.active_last_90_days_in_months,0),1) AS prospects_last_90_months_active,
        baf.listings_last_90_days/coalesce(nullif(baf.prospects_last_90_days,0),1) AS prospects_listings_last_90
    FROM base_aff baf
),
conditional_inactives_new AS (
    SELECT
        *,
        CASE
            WHEN rt.lifetime_days_cohort >= 0 AND rt.lifetime_days_cohort < 10 THEN 'new user'
            WHEN rt.lifetime_days_cohort < 0 THEN 'different cohort'
            WHEN rt.prospects_last_90_days = 0 THEN
                CASE WHEN rt.leads = 0 THEN 'curioso'
                     WHEN rt.listings = 0 THEN 'desconfiado'
                     WHEN rt.conversion_prospect_to_listing > 0.10 THEN 'ex-show'
                     WHEN rt.conversion_prospect_to_listing > 0.01 THEN 'ex-ok'
                     WHEN rt.conversion_prospect_to_listing < 0.01
                       AND rt.conversion_prospect_to_listing > 0 THEN 'ex-perdido'
                     ELSE 'active' END
            ELSE 'active'
        END AS new_inactive
    FROM ratios rt
),
horizontal_vertical_axis AS (
    SELECT
        *,
        CASE
            WHEN new_inactive = 'active' THEN
                CASE WHEN prospects_last_90_months_active >= 100 THEN 3
                     WHEN prospects_last_90_months_active < 100
                        AND prospects_last_90_months_active >= 2.5 THEN 2
                     WHEN prospects_last_90_months_active < 2.5 THEN 1
                     ELSE 0 END
            ELSE 0
            END AS eixo_horizontal,
        CASE
            WHEN new_inactive = 'active' THEN
                CASE WHEN prospects_listings_last_90 >= 0.10 THEN 3
                     WHEN prospects_listings_last_90 < 0.10
                        AND prospects_listings_last_90 >= 0.01 THEN 2
                     WHEN prospects_listings_last_90 < 0.01 THEN 1
                     ELSE 0 END
            ELSE 0
            END AS eixo_vertical
    FROM conditional_inactives_new
),
full_segmentation AS (
    SELECT
        *,
        -- Next step: Create a dynamic and more self service process to manage current and new segmentation names
        CASE
            WHEN new_inactive <> 'active' THEN new_inactive
            WHEN eixo_horizontal = 1 AND eixo_vertical = 1 THEN 'teste'
            WHEN eixo_horizontal = 1 AND eixo_vertical = 2 THEN 'fantasma'
            WHEN eixo_horizontal = 1 AND eixo_vertical = 3 THEN 'certeiro'
            WHEN eixo_horizontal = 2 AND eixo_vertical = 1 THEN 'perdido'
            WHEN eixo_horizontal = 2 AND eixo_vertical = 2 THEN 'captador'
            WHEN eixo_horizontal = 2 AND eixo_vertical = 3 THEN 'corretor'
            WHEN eixo_horizontal = 3 AND eixo_vertical = 1 THEN 'volume-erro'
            WHEN eixo_horizontal = 3 AND eixo_vertical = 2 THEN 'volume-ok'
            WHEN eixo_horizontal = 3 AND eixo_vertical = 3 THEN 'estrela'
            ELSE 'sem-segmentacao'
        END AS segmentation
    FROM horizontal_vertical_axis
)
SELECT
    sk_date,
    sk_user_affiliate,
    sk_user,
    segmentation,
    is_last_segmentation
FROM full_segmentation
WHERE sk_date <= cast(to_char(ADD_MONTHS('{0}'::DATE, 1) ,'YYYYMMDD') as integer)
;