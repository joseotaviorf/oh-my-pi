WITH adjusted_window_partitions AS (
    SELECT 
        id_partner,
        portfolio_user_name,
        cluster_name,
        ts_created,
        ROW_NUMBER() OVER (PARTITION BY id_partner, portfolio_user_name, cluster_name ORDER BY ts_created) - 
        ROW_NUMBER() OVER (PARTITION BY id_partner ORDER BY ts_created) AS partition_value
    FROM 
        datalake_gsheets_clean.ciq_portfolio
),
first_start_dates_by_partitions AS (
    SELECT 
        id_partner,
        portfolio_user_name,
        cluster_name,
        partition_value,
        MIN(DATE(ts_created)) AS dt_start
    FROM 
        adjusted_window_partitions
    GROUP BY
        1,2,3,4
),
end_date_by_partitions AS (
    SELECT 
        id_partner,
        portfolio_user_name,
        cluster_name,
        dt_start,
        LEAD(dt_start) OVER (PARTITION BY id_partner ORDER BY dt_start) AS dt_end
    FROM 
        first_start_dates_by_partitions
)
SELECT 
    id_partner,
    portfolio_user_name,
    cluster_name,
    CASE
      WHEN dt_end IS NULL THEN TRUE
      ELSE FALSE
    END is_last_status,
    dt_start,
    dt_end
FROM
    end_date_by_partitions