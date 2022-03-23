WITH
--------------------------------
----------STATUS DAILY----------
--------------------------------
info_status AS (
    SELECT
        id_real_estate_agency::INT,
        ts_created,
        CASE WHEN ROW_NUMBER() OVER (PARTITION BY id_real_estate_agency ORDER BY ts_created) % 2 = 0 THEN 'Active' ELSE 'Inactive' END AS status
    FROM
        datalake_casa_mineira_portal_clean_prod.real_estate_agency_history
    WHERE
        modified_column = 'desativado_em'
    
    UNION ALL
    
    SELECT
        id::INT id_real_estate_agency,
        ts_created,
        'Active' AS status
    FROM
        datalake_casa_mineira_portal_clean_prod.real_estate_agency
),
status_ts AS (    
        SELECT
            id_real_estate_agency,
            status,
            ts_created AS ts_start,
            LEAD(ts_created) OVER(PARTITION BY id_real_estate_agency ORDER BY ts_created) AS ts_end
        FROM
            info_status
),
status AS (
    SELECT
        date,
        week_start,
        month_start,
        id_real_estate_agency AS advertiser_id,
        r.real_estate_agency_name AS advertiser_name,
        uf.uf_initials AS advertiser_uf,
        ct.city_name AS advertiser_city,
        status
    FROM
        status_ts
    JOIN dim_date
        ON date BETWEEN ts_start::DATE
        AND COALESCE(ts_end::DATE, CURRENT_DATE) - 1
    LEFT JOIN
        datalake_casa_mineira_portal_clean_prod.real_estate_agency AS r
        ON r.id=status_ts.id_real_estate_agency
    LEFT JOIN
        datalake_casa_mineira_portal_clean_prod.city AS ct
        ON r.id_city = ct.id
    LEFT JOIN
        datalake_casa_mineira_portal_clean_prod.uf AS uf
        ON ct.id_uf = uf.id
),
--------------------------------
----------BUDGET DAILY----------
--------------------------------
info_budget AS (
    SELECT  
        b.id_real_estate_agency::INT,
        b.ts_created,
        r.ts_disabled,
        b.budget_value,
        LEAD(b.ts_created) OVER(PARTITION BY b.id_real_estate_agency ORDER BY b.ts_created) AS ts_next_change
    FROM
        datalake_casa_mineira_portal_clean_prod.real_estate_agency_budget AS b
    JOIN
        datalake_casa_mineira_portal_clean_prod.real_estate_agency AS r
        ON r.id=b.id_real_estate_agency
),
budget AS (
    SELECT
        date,
        id_real_estate_agency AS advertiser_id,
        budget_value / (DATE_DIFF('DAY', month_start, month_end) + 1)::FLOAT AS daily_budget
    FROM
        info_budget AS b
    JOIN dim_date
    ON date BETWEEN ts_created::DATE AND COALESCE(ts_next_change::DATE, ts_disabled::DATE, CURRENT_DATE) - 1
),
--------------------------------
----------LISTINGS DAILY--------
--------------------------------
listings AS (
    SELECT
        date,
        h.id_real_estate_agency::INT AS advertiser_id,
        COUNT(DISTINCT h.id) AS published_listings
    FROM
        datalake_casa_mineira_portal_clean_prod.house AS h
    JOIN
        dim_date
        ON date BETWEEN ts_created::DATE
        AND COALESCE(ts_disabled::DATE, CURRENT_DATE) - 1
    WHERE
        date BETWEEN DATE_ADD('YEAR', -1, CURRENT_DATE) AND DATE_ADD('DAY', -1, CURRENT_DATE)
    GROUP BY 1,2
)
----------------------------------
-----------FINAL TABLE------------
----------------------------------
SELECT
    s.date,
    s.week_start,
    s.month_start,
    s.advertiser_id,
    s.advertiser_name,
    s.advertiser_uf,
    s.advertiser_city,
    s.status,
    SUM(b.daily_budget) AS daily_budget,
    SUM(l.published_listings) AS published_listings
FROM
    status AS s
LEFT JOIN
    budget AS b
    ON s.date=b.date
    AND s.advertiser_id=b.advertiser_id
LEFT JOIN
    listings AS l
    ON s.date=l.date
    AND s.advertiser_id=l.advertiser_id
GROUP BY 1,2,3,4,5,6,7,8
