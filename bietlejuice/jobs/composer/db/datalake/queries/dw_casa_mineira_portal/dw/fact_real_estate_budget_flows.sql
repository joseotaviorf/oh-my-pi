WITH deactivation_period AS (
    SELECT
        id_real_estate_agency,
        dt_consider_status_started,
        dt_consider_status_ended
    FROM 
        datalake_casa_mineira_portal.real_estate_status
    WHERE 
        status != 'DISABLED'
),
info_budget AS (
    SELECT 
        CAST(id_real_estate_agency AS INT),
        budget_value,
        CAST(DATE_TRUNC('month',
            LEAD(rea_budget.ts_created)
            OVER(
                PARTITION BY 
                    id_real_estate_agency
                ORDER BY 
                    rea_budget.ts_created
            ))
            AS DATE
        ) AS dt_next_month_started,
        CAST(DATE_TRUNC('month', rea_budget.ts_created) AS DATE) AS dt_creation,
        CAST(DATE_TRUNC('month', agency.ts_disabled) AS DATE) AS dt_deactivation,
        rea_budget.ts_created
    FROM
        datalake_casa_mineira_portal_clean.real_estate_agency_budget AS rea_budget
    JOIN datalake_casa_mineira_portal_clean.real_estate_agency AS agency
        ON rea_budget.id_real_estate_agency = agency.id
),
budget AS (
    SELECT /*+ RANGE_JOIN(info_budget, 300) */ DISTINCT 
        id_real_estate_agency AS sk_real_estate_agency,
        CAST(DATE_FORMAT(month_start, 'yyyyMMdd') AS INT) AS sk_month_started_date,
        CAST(budget_value AS FLOAT) AS month_budget,
        month_start AS dt_month_started
    FROM 
        info_budget
    JOIN
        datalake_quintoandar.aux_date
            ON date BETWEEN dt_creation
            AND (
                    CASE
                        WHEN dt_deactivation IS NULL
                            THEN COALESCE(DATE_SUB(CAST(dt_next_month_started AS DATE), 1), ADD_MONTHS(DATE_TRUNC('MONTH', CURRENT_DATE), 1))
                        ELSE DATE_SUB(COALESCE(CAST(dt_next_month_started AS DATE), CAST(dt_deactivation AS DATE)), 1)
                    END
                )
),
budget_flows AS (
    SELECT
        budget.*
    FROM 
        budget
    INNER JOIN -- Only consider periods in which the real estate agency was active
        deactivation_period
            ON budget.sk_real_estate_agency = deactivation_period.id_real_estate_agency
                AND (budget.dt_month_started
                        BETWEEN deactivation_period.dt_consider_status_started
                        AND COALESCE(deactivation_period.dt_consider_status_ended, ADD_MONTHS(DATE_TRUNC('MONTH', CURRENT_DATE), 1)) 
                    ) 
)
SELECT 
    CAST(CONCAT(sk_real_estate_agency, sk_month_started_date) AS BIGINT) AS sk_real_estate_budget_flow,
    sk_real_estate_agency,
    sk_month_started_date,
    month_budget,
    dt_month_started,
    NOW() AS ts_load
FROM 
    budget_flows
