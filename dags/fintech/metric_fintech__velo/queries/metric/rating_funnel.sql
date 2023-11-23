WITH ES AS (
    SELECT
        DATE_TRUNC('week',DATE(ts_evaluation_started)) AS dt_es,
        r.rating,
        COUNT(ph.sk_propose) AS Total_es
    FROM
        dw_velo.fact_velo_propose AS ph
    LEFT JOIN
        datalake_velo.neurotech_rating AS r
            ON r.proposal_id = ph.sk_propose
    GROUP BY
        1,2

), CA AS (
    SELECT
        DATE_TRUNC('week',DATE(ts_sign_started)) AS dt_ca,
        r.rating,
        COUNT(ph.sk_propose) AS Total_ca
    FROM
        dw_velo.fact_velo_propose AS ph
    LEFT JOIN
        datalake_velo.neurotech_rating AS r
            ON r.proposal_id = ph.sk_propose
    GROUP BY
        1, 2
), CS AS (
    SELECT
        DATE_TRUNC('week',dt_contract_started) AS dt_cs,
        r.rating,
        COUNT(ph.sk_propose) AS Total_cs
    FROM
        dw_velo.fact_velo_propose AS ph
    LEFT JOIN
        datalake_velo.neurotech_rating AS r
            ON r.proposal_id = ph.sk_propose
    GROUP BY
        1, 2

), date_rating AS (
    SELECT DISTINCT
        DATE_TRUNC('week', d.date) AS week,
        es.rating AS rating
    FROM
        dw_public.dim_date AS d
    JOIN es
        ON d.date = es.dt_es
)
SELECT
    dr.week,
    dr.rating,
    es.total_es,
    ca.total_ca,
    cs.total_cs
FROM
    date_rating AS dr
LEFT JOIN
    ES AS es
        ON (dr.week = es.dt_es
        AND dr.rating = es.rating)
LEFT JOIN
    CA AS ca
        ON (dr.week = ca.dt_ca
        AND dr.rating = ca.rating)
LEFT JOIN
    CS  AS cs
        ON (dr.week = cs.dt_cs
            AND dr.rating = cs.rating)
WHERE
    CAST(dr.week AS DATE) >= CAST('2022-08-01' AS DATE)
ORDER BY
    1 DESC, 2
