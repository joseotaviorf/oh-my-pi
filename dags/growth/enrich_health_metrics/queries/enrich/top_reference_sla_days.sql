WITH max_sla_achieved AS (
    SELECT
        dag_owner,
        MAX(ratio_sla_ok) AS max_sla_achieved
    FROM 
        datalake_health_metrics.daily_sla_metrics
    WHERE
        dt_executed >= CURRENT_DATE() - INTERVAL '1' MONTH
    GROUP BY
        1      
),
top_reference_sla_days AS (
    SELECT 
        dsm.dag_owner,
        dsm.dt_executed,
        ratio_sla_ok,
        max_sla_achieved,
        RANK() OVER(PARTITION BY dsm.dag_owner ORDER BY dsm.dt_executed DESC) AS rank
    FROM
        datalake_health_metrics.daily_sla_metrics AS dsm
    JOIN
        max_sla_achieved AS msa
    ON
        dsm.dag_owner = msa.dag_owner
    WHERE
        dt_executed >= CURRENT_DATE() - INTERVAL '6' MONTH
        AND dsm.ratio_sla_ok >= msa.max_sla_achieved
    QUALIFY 
        rank <= 20
)
SELECT 
    dag_owner,
    dt_executed
FROM
    top_reference_sla_days