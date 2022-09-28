WITH projected_weeks AS (
    SELECT 
        weeks.weeks_since_listing_started,
        CAST(7*weeks.weeks_since_listing_started AS INT) AS days_since_listing_started
    FROM
        RANGE(1,29) AS weeks(weeks_since_listing_started)
),
mkt_house AS (
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
        r.city_group,
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
                            WHEN hldi.doorman_type in ('horas24','Diurno')  THEN ' Com Portaria' 
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
        CASE
            WHEN LOWER(hldi.status_change_reason) RLIKE 'minuta|reservado|nogocia|proposta' THEN 'nogociacao avancada'
            WHEN LOWER(hldi.status_change_reason) RLIKE 'disabled|erro ao|despublicação automática após rescisão|\\[auto\\] \\[rescisao\\]' THEN 'opt out / erro'
            ELSE hldi.status_history
        END AS status_history,
        pw.weeks_since_listing_started, -- cohort 0 to 7 days => 1w, 8 to 14days  => 2w
        MAX(hldi.dt_day) OVER(PARTITION BY hldi.id_house_listing, pw.weeks_since_listing_started) = hldi.dt_day AS is_last_status_in_cohort,
        DATE_TRUNC('month', dhl.ts_listing_version_start) AS dt_listing_month_started,
        DATE_TRUNC('week', dhl.ts_listing_version_start) AS dt_listing_week_started,
        hldi.ts_status_started,
        dhl.ts_listing_version_start
    FROM
        dw_public.dim_house_listing AS dhl
    JOIN
        datalake_rental_historical_follow_up.house_listings_daily_info AS hldi
            ON dhl.sk_house_listing = hldi.id_house_listing
    JOIN
        projected_weeks AS pw
            ON DATE(CONCAT(hldi.year, '-', hldi.month, '-', hldi.day)) <= DATE_ADD(dhl.ts_listing_version_start, pw.days_since_listing_started)
    LEFT JOIN
        mkt_house AS mkt
            ON mkt.id_house = hldi.id_house
    LEFT JOIN
        datalake_ebdb_clean.occupant_type AS ot
            ON hldi.id_occupant = ot.id
    LEFT JOIN
        datalake_region.region AS r
            ON hldi.id_region = r.id

    WHERE
        dhl.ts_listing_version_start >= DATE('{year}-{month}-{day}') - INTERVAL 90 WEEK
        AND DATE(CONCAT(hldi.year, '-', hldi.month, '-', hldi.day)) >= DATE('{year}-{month}-{day}') - INTERVAL 90 WEEK -- PartitionFilters
        AND dhl.country_code = 'BR'
        AND r.city_group IS NOT NULL 
),
listing_first_group AS (
/*
We are fixing the first group which a listing belongs
as a reference. So any other week considers this first
group, regardless any change in this listing.
In this way, we keep only the listing status changing over time.
*/
    SELECT
        id_house_listing,
        city_group,
        consultant_type,
        entry_condition,
        exclusivity,
        hybrid,
        listing_category_start,
        mkt_completion,
        mkt_origin,
        dt_listing_month_started,
        dt_listing_week_started
    FROM
        weekly_status_since_start
    WHERE
        is_last_status_in_cohort = TRUE
        AND weeks_since_listing_started = 1
),
weekly_amounts AS (
    SELECT
        MD5(lfg.dt_listing_week_started || lfg.dt_listing_month_started || lfg.listing_category_start || lfg.city_group || lfg.hybrid || lfg.mkt_completion || lfg.mkt_origin || lfg.entry_condition || lfg.consultant_type || lfg.exclusivity) AS id_cohort_listing,
        lfg.city_group,
        lfg.consultant_type,
        lfg.entry_condition,
        lfg.exclusivity,
        lfg.hybrid,
        lfg.listing_category_start,
        lfg.mkt_completion,
        lfg.mkt_origin,
        COUNT(DISTINCT wsss.id_house_listing) AS imoveis_w,
        COUNT(DISTINCT IF(wsss.status_history = 'alugado', wsss.id_house_listing, NULL)) AS list_w_cs_w,
        COUNT(DISTINCT IF(wsss.status_history = 'despublicado', wsss.id_house_listing, NULL)) AS depub_w,
        COUNT(DISTINCT IF(wsss.status_history = 'suspenso', wsss.id_house_listing, NULL)) AS suspenso_w,
        wsss.weeks_since_listing_started,
        lfg.dt_listing_month_started,
        lfg.dt_listing_week_started
    FROM
        weekly_status_since_start AS wsss
    JOIN
        listing_first_group AS lfg
            ON wsss.id_house_listing = lfg.id_house_listing
    WHERE
        is_last_status_in_cohort = TRUE
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15, 16
)
SELECT
    id_cohort_listing || weeks_since_listing_started AS id_cohort_listing_week,
    id_cohort_listing,
    city_group,
    consultant_type,
    entry_condition,
    exclusivity,
    hybrid,
    listing_category_start,
    mkt_completion,
    mkt_origin,
    depub_w,
    imoveis_w,
    list_w_cs_w,
    suspenso_w,
    weeks_since_listing_started,
    dt_listing_month_started,
    dt_listing_week_started
FROM
    weekly_amounts