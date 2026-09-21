WITH journey_nps AS (
    SELECT
        date_trunc('month', CAST(dna.ts_answered AS TIMESTAMP)) AS ref_month,
        CASE
            WHEN dnc.metric_group LIKE '%onboarding%'  THEN 'onboarding'
            WHEN dnc.metric_group LIKE '%ongoing%'     THEN 'ongoing'
            WHEN dnc.metric_group LIKE '%offboarding%' THEN 'offboarding'
        END AS journey,
        COUNT(DISTINCT dna.sk_nps_answer) AS total_answers,
        ROUND(
            (CAST(COUNT(DISTINCT CASE WHEN dna.score_category = 'promoter'  THEN dna.sk_nps_answer END) AS DOUBLE)
           - CAST(COUNT(DISTINCT CASE WHEN dna.score_category = 'detractor' THEN dna.sk_nps_answer END) AS DOUBLE))
            / COUNT(DISTINCT dna.sk_nps_answer) * 100, 1
        ) AS nps_journey
    FROM dw_customer_satisfaction.fact_nps_dispatches AS fnd
    INNER JOIN dw_customer_satisfaction.dim_nps_answer AS dna
        ON fnd.sk_nps_answer = dna.sk_nps_answer
    INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS dnc
        ON fnd.sk_nps_campaign = dnc.sk_nps_campaign
    WHERE fnd.is_answered = true
      AND dnc.business_context = 'forRent'
      AND dnc.customer_journey = 'true'
      AND dnc.purpose = 'main'
      AND CAST(dna.ts_answered AS TIMESTAMP) >= CAST(current_date - INTERVAL '24' MONTH AS TIMESTAMP)
      AND CAST(dna.ts_answered AS TIMESTAMP) < CAST(current_date AS TIMESTAMP)
    GROUP BY 1, 2
),
weights_raw AS (
    SELECT
        campaign_group AS journey,
        CAST(dt_start AS DATE) AS dt_start,
        CAST(dt_end AS DATE) AS dt_end,
        CAST(REPLACE(share, '%', '') AS DOUBLE) / 100.0 AS weight
    FROM datalake_gsheets_clean.nps_target_share
    WHERE customer_journey = 'TRUE'
      AND share IS NOT NULL
      AND share != ''
),
latest_weights AS (
    SELECT journey, weight
    FROM (
        SELECT
            journey,
            weight,
            ROW_NUMBER() OVER (PARTITION BY journey ORDER BY dt_end DESC) AS rn
        FROM weights_raw
    ) AS sub
    WHERE rn = 1
),
journey_with_weight AS (
    SELECT
        jn.ref_month,
        jn.journey,
        jn.nps_journey,
        jn.total_answers,
        w.weight,
        ROW_NUMBER() OVER (
            PARTITION BY jn.ref_month, jn.journey
            ORDER BY w.dt_start DESC, w.dt_end DESC
        ) AS rn
    FROM journey_nps AS jn
    LEFT JOIN weights_raw AS w
        ON jn.journey = w.journey
       AND CAST(jn.ref_month AS DATE) BETWEEN w.dt_start AND w.dt_end
)
SELECT
    d.ref_month,
    ROUND(SUM(d.nps_journey * COALESCE(d.weight, lw.weight)), 1) AS nps_true,
    SUM(d.total_answers) AS total_answers,
    MIN(CASE WHEN d.weight IS NULL THEN 'fallback' ELSE 'official' END) AS weight_source
FROM (SELECT * FROM journey_with_weight WHERE rn = 1) AS d
LEFT JOIN latest_weights AS lw
    ON d.journey = lw.journey
GROUP BY d.ref_month
ORDER BY d.ref_month
