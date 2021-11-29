WITH date_month_range AS (
    SELECT DISTINCT
        d.id_date,
        d.month_end AS dt_month_end,
        d.month_start AS dt_month_start
    FROM 
        datalake_quintoandar.aux_date AS d
    WHERE  
        d.month_start = d.date
        AND d.date BETWEEN ADD_MONTHS('{year}-{month}-{day}', -17) AND ADD_MONTHS('{year}-{month}-{day}', 1)
),
base_aff AS (
    SELECT
        u.id_affiliates,
        dt.id_date,
        ad.id AS id_user_affiliate,
        u.id AS id_user,
        ad.affiliate_type,
        CAST(
            COUNT(
                DISTINCT CASE 
                            WHEN lfwrl.ts_prospect IS NOT NULL 
                                AND dt_prospect.DATE BETWEEN DATE(ADD_MONTHS(dt.dt_month_start,-3)) 
                                AND DATE(LAST_DAY(ADD_MONTHS(dt.dt_month_end,-1))) THEN dt_prospect.month 
                         END
            ) AS FLOAT) AS active_last_90_days_in_months,
        DATEDIFF(dt.dt_month_start, DATE(ad.ts_operation_start)) AS lifetime_days_cohort,
        CAST(
            COUNT(
                DISTINCT CASE 
                            WHEN lfwrl.ts_lead IS NOT NULL 
                                AND dt_lead.DATE < dt.dt_month_start THEN lfwrl.id 
                         END
            ) AS FLOAT) AS leads,
        CAST(
            COUNT(
                DISTINCT 
                    CASE   
                        WHEN lfwrl.ts_first_listing IS NOT NULL 
                            AND dt_listing.DATE < dt.dt_month_start THEN lfwrl.id 
                    END
            ) AS FLOAT)
        AS listings,
        CAST(
            COUNT(
                DISTINCT CASE 
                            WHEN lfwrl.ts_first_listing IS NOT NULL 
                                AND dt_listing.DATE BETWEEN DATE(ADD_MONTHS(dt.dt_month_start,-3))
                                AND LAST_DAY(ADD_MONTHS(dt.dt_month_end,-1)) THEN lfwrl.id
                         END
            ) AS FLOAT) AS listings_last_90_days,
        CAST(
            COUNT(
                DISTINCT CASE 
                            WHEN lfwrl.ts_prospect IS NOT NULL 
                                AND dt_prospect.DATE < dt.dt_month_start THEN lfwrl.id 
                         END
            ) AS FLOAT ) AS prospects,
        CAST(
            COUNT(
                DISTINCT CASE 
                            WHEN lfwrl.ts_prospect IS NOT NULL 
                                AND dt_prospect.DATE BETWEEN DATE(ADD_MONTHS(dt.dt_month_start,-3)) 
                                AND LAST_DAY(ADD_MONTHS(dt.dt_month_end,-1)) THEN lfwrl.id 
                         END
            ) AS FLOAT) AS prospects_last_90_days,
        RANK() OVER(PARTITION BY ad.id ORDER BY dt.dt_month_start DESC) = 1 AS is_last_segmentation,
        dt.dt_month_end,
        dt.dt_month_start,
        DATE(ad.ts_operation_start) AS dt_signed
    FROM 
        datalake_ebdb_user.affiliate_data AS ad
    CROSS JOIN 
        date_month_range AS dt
    JOIN 
        datalake_ebdb_clean.user u
            ON u.id_affiliates = ad.id
    LEFT JOIN 
        datalake_listing_flow.listing_flows_with_reprocessed_leads AS lfwrl
            ON COALESCE(lfwrl.id_affiliate, lfwrl.id_user_has_indicated) = u.id
    LEFT JOIN 
        datalake_quintoandar.aux_date AS dt_lead
            ON dt_lead.id_date = COALESCE(CAST(DATE_FORMAT(lfwrl.ts_lead,'yyyyMMdd') AS BIGINT), -1)
    LEFT JOIN 
        datalake_quintoandar.aux_date AS dt_prospect
            ON dt_prospect.id_date = COALESCE(CAST(DATE_FORMAT(lfwrl.ts_prospect,'yyyyMMdd') AS BIGINT), -1)
    LEFT JOIN 
        datalake_quintoandar.aux_date AS dt_listing
            ON dt_listing.id_date = COALESCE(CAST(DATE_FORMAT(lfwrl.ts_first_listing,'yyyyMMdd') AS BIGINT), -1)
    WHERE 
        ad.affiliate_type IN ('Standard', 'Agent')
    GROUP BY 1,2,3,4,5,7,14, 15, 16
)
SELECT
    id_date,
    id_user_affiliate,
    id_user,
    affiliate_type,
    listings/COALESCE(NULLIF(leads,0),1) AS conversion_lead_to_listing,
    listings/COALESCE(NULLIF(prospects,0),1) AS conversion_prospect_to_listing,
    active_last_90_days_in_months,
    lifetime_days_cohort,
    leads,
    listings,
    listings_last_90_days,
    prospects,
    prospects_last_90_days,
    prospects_last_90_days/COALESCE(NULLIF(active_last_90_days_in_months,0),1) AS prospects_last_90_months_active,
    listings_last_90_days/COALESCE(NULLIF(prospects_last_90_days,0),1) AS prospects_listings_last_90,
    is_last_segmentation,
    dt_month_end,
    dt_month_start,
    dt_signed
FROM 
    base_aff