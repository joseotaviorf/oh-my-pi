WITH base AS (
    SELECT
        rf.sk_client,
        rf.sk_rent_flow,
        vs.ts_schedule_created AS dt_booking_created,
        do.dt_created AS dt_offer_sent,
        dc.ts_signature AS dt_contract_signed
    FROM
        dw_rent.fact_listing_rent_flows AS rf
    LEFT JOIN
        datalake_visit.visit_schedules AS vs
            ON rf.sk_booking = vs.id_schedule
            AND vs.business_context = 'RENT'
    LEFT JOIN
        dw_rent.dim_offer AS do
            ON rf.sk_offer = do.sk_offer
            AND (do.country_code = 'BR' OR do.country_code IS NULL)
    LEFT JOIN
        dw_rent.dim_contract AS dc
            ON rf.sk_contract = dc.sk_contract
    INNER JOIN
        dw_public.dim_region AS dr
            ON dr.sk_region = rf.sk_region
            AND (dr.country_code = 'BR' OR dr.country_code IS NULL)
    WHERE
        rf.sk_client > 0
),
first_interaction AS (
    SELECT
        *,
        CASE
            WHEN dt_booking_created < dt_offer_sent THEN dt_booking_created
            WHEN dt_offer_sent < dt_booking_created THEN dt_offer_sent
            ELSE COALESCE(dt_booking_created,dt_offer_sent)
        END AS dt_first_interaction
    FROM
        base
),
base_adjust AS (
    SELECT
        sk_client,
        MIN(dt_first_interaction) AS dt_first_interaction,
        MIN(dt_contract_signed) AS dt_first_contract_signed
    FROM
        first_interaction
    GROUP BY 1
)
SELECT
    DATE(DATE_TRUNC('month', dt_first_interaction)) AS dt_month_started,
    COUNT(
        DISTINCT
            CASE
                WHEN DATEDIFF(dt_first_interaction, dt_first_contract_signed) <= 28 THEN sk_client
            END
        )/ CAST(
                COUNT(
                    DISTINCT
                        CASE
                            WHEN dt_first_interaction IS NOT NULL THEN sk_client
                        END)
                AS DOUBLE
            ) AS ntp2cs
FROM
    base_adjust
GROUP BY 1
ORDER BY 1 DESC
