WITH
--------------------------------
----------STATUS DAILY----------
--------------------------------
info_status as (
    SELECT
        id_real_estate_agency::INT,
        ts_created,
        CASE WHEN row_number() OVER (PARTITION BY id_real_estate_agency ORDER BY ts_created) % 2 = 0 THEN 'Active' ELSE 'Inactive' END AS status
    FROM datalake_casa_mineira_portal_clean_prod.real_estate_agency_history
    WHERE modified_column = 'desativado_em'
    
    UNION ALL
    
    SELECT
        id::INT id_real_estate_agency,
        ts_created,
        'Active' as status
    FROM datalake_casa_mineira_portal_clean_prod.real_estate_agency
),
status_ts as (    
        SELECT
            id_real_estate_agency,
            status,
            ts_created AS ts_start,
            LEAD(ts_created) OVER(PARTITION BY id_real_estate_agency ORDER BY ts_created) AS ts_end
        FROM info_status
),
status as (
    SELECT
        date,
        week_start,
        id_real_estate_agency as advertiser_id,
        r.real_estate_agency_name as advertiser_name,
        uf.uf_initials as advertiser_uf,
        ct.city_name as advertiser_city,
        status,
        NULL::FLOAT AS daily_budget,
        NULL::INT AS published_listings
    FROM status_ts
    JOIN dim_date
        ON date BETWEEN ts_start::DATE AND COALESCE(ts_end::DATE, CURRENT_DATE) - 1
    LEFT JOIN datalake_casa_mineira_portal_clean_prod.real_estate_agency r
        ON r.id=status_ts.id_real_estate_agency
    LEFT JOIN datalake_casa_mineira_portal_clean_prod.city AS ct
        ON r.id_city = ct.id
    LEFT JOIN datalake_casa_mineira_portal_clean_prod.uf AS uf
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
        r.real_estate_agency_name,
        uf.uf_initials,
        ct.city_name,
        LEAD(b.ts_created) OVER(PARTITION BY b.id_real_estate_agency ORDER BY b.ts_created) AS ts_next_change
    FROM datalake_casa_mineira_portal_clean_prod.real_estate_agency_budget b
        JOIN datalake_casa_mineira_portal_clean_prod.real_estate_agency r
            ON r.id=b.id_real_estate_agency
        LEFT JOIN datalake_casa_mineira_portal_clean_prod.city AS ct
            ON r.id_city = ct.id
        LEFT JOIN datalake_casa_mineira_portal_clean_prod.uf AS uf
            ON ct.id_uf = uf.id
),
budget as (
    SELECT
        date,
        week_start,
        id_real_estate_agency as advertiser_id,
        real_estate_agency_name as advertiser_name,
        uf_initials as advertiser_uf,
        city_name as advertiser_city,
        NULL::TEXT AS status,
        budget_value / (DATE_DIFF('DAY', month_start, month_end) + 1)::FLOAT as daily_budget,
        NULL::INT AS published_listings
    FROM info_budget b
        JOIN dim_date
            ON date BETWEEN ts_created::DATE AND COALESCE(ts_next_change::DATE, ts_disabled::DATE, CURRENT_DATE) - 1
),
--------------------------------
----------LISTINGS DAILY--------
--------------------------------
listings as (
SELECT
    date,
    week_start,
    h.id_real_estate_agency::INT as advertiser_id,
    r.real_estate_agency_name as advertiser_name,
    uf.uf_initials as advertiser_uf,
    ct.city_name as advertiser_city,
    NULL::TEXT AS status,
    NULL::FLOAT AS daily_budget,
    COUNT(DISTINCT h.id) AS published_listings
FROM datalake_casa_mineira_portal_clean_prod.house h
    JOIN dim_date
        ON date BETWEEN ts_created::DATE AND COALESCE(ts_disabled::DATE, CURRENT_DATE) - 1
    LEFT JOIN datalake_casa_mineira_portal_clean_prod.real_estate_agency AS r
        ON h.id_real_estate_agency = r.id
    LEFT JOIN datalake_casa_mineira_portal_clean_prod.city AS ct
        ON r.id_city = ct.id
    LEFT JOIN datalake_casa_mineira_portal_clean_prod.uf AS uf
        ON ct.id_uf = uf.id
WHERE date BETWEEN DATE_ADD('YEAR', -1, CURRENT_DATE) AND DATE_ADD('DAY', -1, CURRENT_DATE)
GROUP BY 1,2,3,4,5,6
)
--------------------------------
-----------UNION ALL------------
--------------------------------
SELECT * FROM status 
UNION ALL
SELECT * FROM budget 
UNION ALL
SELECT * FROM listings