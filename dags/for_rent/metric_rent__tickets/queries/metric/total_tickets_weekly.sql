WITH contract_signed AS (
    SELECT
        SUM(new_contracts_signed) AS new_contracts_signed,
        DATE(DATE_TRUNC('week', day)) AS dt_week
    FROM
        metric_rent.new_contracts_signed_daily
    WHERE
        day >= DATE('2022-01-01')
        AND country_code = 'BR'
    GROUP BY 2
), 
ccv AS (
    SELECT 
        COUNT(DISTINCT CASE WHEN fo.sk_sale_agreement_signed_date > 0 THEN sk_offer END) AS ccvs,
        dd.week_start AS dt_week
    FROM 
        dw_sale.fact_offers fo
    INNER JOIN 
        dw_public.dim_date dd 
            ON dd.sk_date = fo.sk_sale_agreement_signed_date
    WHERE
        sk_date >= 20220101
    GROUP BY 2
),
aux_ongoing_rentals AS (
    SELECT
        MAX(day) AS dt_last_day,
        DATE(DATE_TRUNC('week', day)) AS dt_week
    FROM
        metric_rent.ongoing_rentals_daily
    GROUP BY 2
),
ongoing_rentals AS (
    SELECT DISTINCT
        o.ongoing_rentals,
        a.dt_week
    FROM
        metric_rent.ongoing_rentals_daily AS o
    INNER JOIN
        aux_ongoing_rentals AS a
            ON a.dt_last_day = o.day
    WHERE
        o.day >= DATE('2022-01-01')
        AND o.country_code = 'BR'
),
ended_rentals AS (
    SELECT
        SUM(ended_rentals_confirmed) AS ended_rentals,
        DATE(DATE_TRUNC('week', day)) AS dt_week
    FROM 
        metric_rent.ended_rentals_confirmed_daily
    WHERE 
        day >= DATE('2022-01-01')
        AND country_code = 'BR'
    GROUP BY 2
),
drivers AS (
    SELECT DISTINCT
        cs.new_contracts_signed,
        ccv.ccvs,
        ors.ongoing_rentals,
        ers.ended_rentals,
        d.week_start AS dt_week
    FROM
        dw_public.dim_date AS d 
    LEFT JOIN
        contract_signed AS cs 
            ON cs.dt_week = d.week_start
    LEFT JOIN 
        ccv
            ON ccv.dt_week = d.week_start
    LEFT JOIN 
        ongoing_rentals ors
            ON ors.dt_week = d.week_start
    LEFT JOIN 
        ended_rentals ers
            ON ers.dt_week = d.week_start
    WHERE
        d.sk_date >= 20220101
),
total_tickets_prep AS (
    SELECT 
        DATE(DATE_TRUNC('week', ts_solved)) AS dt_week,
        CASE 
            WHEN dt.sub_journey NOT IN ('Partners', 'For Sale') THEN 'ForRent'
            WHEN dt.sub_journey IN ('For Sale') THEN 'ForSale'
            WHEN dt.sub_journey IN ('Partners') THEN dt.sub_journey
            ELSE NULL
        END AS context,
        dt.journey,
        dt.sub_journey,
        dt.line_owner,
        dd.team,
        dd.department,
        dd.front_or_back AS ticket_type,
        dt.theme,
        dt.theme_detail,
        CASE
            WHEN dt.sub_journey IN ('Listing & Search', 'Visits to Offer', 'Contract to Entrance', 'Onboarding') THEN dv.new_contracts_signed
            WHEN dt.sub_journey = 'For Sale' THEN dv.ccvs
            WHEN dt.sub_journey = 'Partners' THEN (dv.new_contracts_signed + dv.ccvs)
            WHEN dt.sub_journey = 'Ongoing' THEN dv.ongoing_rentals
            WHEN dt.sub_journey = 'Offboarding' THEN dv.ended_rentals
            ELSE NULL 
        END AS driver,
        COUNT(ft.sk_ticket) AS total_tickets_pure,
        SUM(ft.total_tickets_proportional) AS total_tickets_proportional
    FROM 
        dw_customer_support.fact_ticket AS ft 
    LEFT JOIN
        dw_customer_support.dim_taxonomy AS dt
            ON ft.sk_taxonomy = dt.sk_taxonomy 
    LEFT JOIN 
        dw_customer_support.dim_department AS dd 
            ON ft.sk_main_department = dd.sk_department
    LEFT JOIN 
        drivers AS dv
            ON DATE(DATE_TRUNC('week', ft.ts_solved)) = dv.dt_week
    WHERE 
        ft.is_ticket_rate = TRUE
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
)
SELECT
    dt_week,
    context,
    journey,
    sub_journey,
    line_owner,
    team,
    department,
    ticket_type,
    theme,
    theme_detail,
    total_tickets_pure,
    total_tickets_proportional,
    (total_tickets_proportional/driver) AS ticket_rate_weekly
FROM 
    total_tickets_prep