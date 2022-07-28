WITH mkt_house AS (
-- We set this to house grain to avoid mess up with
-- the listing grain
    SELECT
        LEFT(sk_house_listing, 9) AS id_house,
        MAX(mkt_completion) AS mkt_completion,
        MAX(mkt_origin) AS mkt_origin 
    FROM
        dw_public.fact_house_listing_flows AS fhlf
    WHERE
        sk_house_listing > 0
    GROUP BY 1
),
weekly_status_since_start AS (
    SELECT
        hldi.id_house_listing,   
        CASE 
            WHEN hldi.consultant_type IS NULL THEN 'Core' 
            ELSE hldi.consultant_type
        END AS consultant_type,
        CASE
            WHEN hldi.first_key_location = 'OwnerPresent' 
                OR hldi.first_key_location = 'None' 
                OR hldi.first_key_location IS NULL THEN ('PP Acompanha' ||
                    CASE 
                        WHEN ot.name = 'Empty' 
                            OR ot.name = 'None' THEN ' Vago' 
                        ELSE 'Ocupado' 
                    END ||
                        CASE
                            WHEN hldi.doorman_type in ('horas24','Diurno') 
                                AND (ot.name = 'Empty' OR ot.name = 'None') THEN ' Com Portaria' 
                            ELSE ' Sem Portaria' 
                        END)
            ELSE hldi.first_key_location 
        END AS entry_condition,
        CASE
            WHEN hldi.is_exclusive THEN 'Exclusivo' 
            ELSE 'Não Exclusivo' 
        END AS exclusivity,
        CASE
            WHEN hldi.is_for_rent = TRUE 
                AND hldi.is_for_sale = TRUE THEN 'Hibrido'
            WHEN hldi.is_for_rent = TRUE 
                AND hldi.is_for_sale = FALSE THEN 'For Rent'
        END AS hybrid,
        dhl.listing_category_start,
        mkt.mkt_completion,
        mkt.mkt_origin,
        hldi.status_history,
        CASE
            WHEN hldi.status_history = 'suspenso'
                AND LOWER(hldi.status_change_reason) RLIKE 'minuta|reservado|nogocia|proposta' THEN 'nogociacao avancada'
            WHEN hldi.status_history = 'despublicado'
                AND LOWER(hldi.status_change_reason) RLIKE 'disabled|erro ao|despublicação automática após rescisão' THEN 'opt out / erro'
            ELSE hldi.status_history
        END AS status_change_mapped,
        CEIL(COALESCE(NULLIF(DATEDIFF(hldi.dt_day, DATE(dhl.ts_listing_version_start)),0), 1)/7.0) AS weeks_since_listing_started, -- cohort 0 to 7 days => 1w, 8 to 14days  => 2w
        MAX(hldi.ts_status_started) OVER(PARTITION BY hldi.id_house_listing, CEIL(COALESCE(NULLIF(DATEDIFF(hldi.dt_day, DATE(dhl.ts_listing_version_start)),0), 1)/7.0)) = hldi.ts_status_started AS is_last_status_in_cohort,
        DATE_TRUNC('month', dhl.ts_listing_version_start) AS dt_listing_month_started,
        DATE_TRUNC('week', dhl.ts_listing_version_start) AS dt_listing_week_started,
        hldi.ts_status_started,
        dhl.ts_listing_version_start
    FROM
        dw_public.dim_house_listing AS dhl
    JOIN
    -- this table already have the last status of a listing in a specific day, so there is no need to treat this on the query.
        datalake_rental_historical_follow_up.house_listings_daily_info AS hldi
            ON dhl.sk_house_listing = hldi.id_house_listing   
               AND (MOD(DATEDIFF(DATE(CONCAT(hldi.year, '-', hldi.month, '-', hldi.day)), DATE(dhl.ts_listing_version_start)), 7) = 0  -- Get cohorts or current run. Obs: It is not pushed to the source
                    OR hldi.dt_day = DATE('{year}-{month}-{day}'))
    LEFT JOIN
        mkt_house AS mkt
            ON mkt.id_house = hldi.id_house
    LEFT JOIN
        datalake_ebdb_clean.occupant_type AS ot
            ON hldi.id_occupant = ot.id 
    WHERE
        dhl.ts_listing_version_start >= DATE('{year}-{month}-{day}') - INTERVAL 90 WEEK
        AND DATE(CONCAT(hldi.year, '-', hldi.month, '-', hldi.day)) >= DATE('{year}-{month}-{day}') - INTERVAL 90 WEEK -- PartitionFilters
        AND dhl.country_code = 'BR'
),
weekly_amounts AS (
    SELECT
        MD5(dt_listing_week_started || listing_category_start || hybrid || mkt_completion || mkt_origin || entry_condition || consultant_type || exclusivity) AS id_cohort_listing,
        consultant_type,
        entry_condition,
        exclusivity,
        hybrid,
        listing_category_start,
        mkt_completion,
        mkt_origin,
        COUNT(DISTINCT id_house_listing) AS imoveis_w,
        COUNT(DISTINCT IF(status_history = 'alugado', id_house_listing, NULL)) AS list_w_cs_w,
        COUNT(DISTINCT IF(status_history = 'despublicado' AND status_change_mapped IS NULL, id_house_listing, NULL)) AS depub_w,
        COUNT(DISTINCT IF(status_history = 'suspenso' AND status_change_mapped IS NULL, id_house_listing, NULL)) AS suspenso_w,
        weeks_since_listing_started,
        dt_listing_month_started,
        dt_listing_week_started
    FROM
        weekly_status_since_start
    WHERE
        is_last_status_in_cohort = TRUE
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 13, 14, 15
),
weekly_conversions AS (
    SELECT
        id_cohort_listing,
        consultant_type,
        entry_condition,
        exclusivity,
        hybrid,
        listing_category_start,
        mkt_completion,
        mkt_origin,
        depub_w,
        imoveis_w,
        IF(imoveis_w = 0, 0, 1.0*list_w_cs_w/imoveis_w) AS l2r_w,
        IF(imoveis_w = 0, 0, 1.0*suspenso_w/imoveis_w) AS l2s_w,
        IF(imoveis_w = 0, 0, 1.0*depub_w/imoveis_w) AS l2u_w,
        list_w_cs_w,
        suspenso_w,
        weeks_since_listing_started,
        dt_listing_month_started,
        dt_listing_week_started
    FROM
        weekly_amounts
    WHERE
        weeks_since_listing_started <= 28
)
SELECT
    id_cohort_listing,
    consultant_type,
    entry_condition,
    exclusivity,
    hybrid,
    listing_category_start,
    mkt_completion,
    mkt_origin,
    depub_w,
    imoveis_w,
    l2r_w,
    l2s_w,
    l2u_w,
    IF(l2r_w = 0, 0, (l2s_w + l2u_w)/(l2s_w + l2u_w + l2r_w)) AS churn_w,
    list_w_cs_w,
    suspenso_w,
    weeks_since_listing_started,
    dt_listing_month_started,
    dt_listing_week_started
FROM
    weekly_conversions