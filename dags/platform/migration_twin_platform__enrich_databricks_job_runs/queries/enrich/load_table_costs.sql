WITH load_tasks AS (
    SELECT 
        tr.id_cluster,
        tr.bietlejuice_dag_name AS dag_name,
        tr.run_name AS task_name,
        t.table AS table_name,
        tr.execution_time_in_seconds,
        SUM(tr.execution_time_in_seconds) OVER (
            PARTITION BY
                tr.bietlejuice_dag_name,
                tr.year,
                tr.month,
                tr.day
        ) AS total_load_tasks_execution_time_in_seconds,
        tr.ts_task_started,
        tr.ts_task_ended,
        tr.year,
        tr.month,
        tr.day
    FROM
        datalake_databricks.task_runs AS tr
    LEFT JOIN
        datalake_dag_inventory_clean.`table` AS t
            ON tr.year = t.year
            AND tr.month = t.month
            AND tr.day = t.day
            AND tr.bietlejuice_dag_name = t.dag
            AND tr.run_name = t.task
    WHERE
        tr.run_name LIKE 'load-%'
        AND MAKE_DATE(tr.year, tr.month, tr.day) BETWEEN '{load_start_date}' AND '{load_end_date}'
        AND tr.terminal_state = 'Succeeded'
),
direct_costs AS (
    SELECT
        ANY_VALUE(lt.dag_name) AS dag_name,
        ANY_VALUE(lt.task_name) AS task_name,
        lt.table_name,
        -- We're attributing the cost of the entire cluster to each individual table by making it proportional
        -- To how much time they take to load. For example, if a single cluster has 2 tables, one takes
        -- X seconds to load and the other takes 9X seconds, the second table will cost 9X times as much.
        SUM(
            dc.total_dbu_cost * (lt.execution_time_in_seconds / lt.total_load_tasks_execution_time_in_seconds)
        ) AS individual_table_dbu_cost,
        SUM(
            dc.total_ec2_cost * (lt.execution_time_in_seconds / lt.total_load_tasks_execution_time_in_seconds)
        ) AS individual_table_ec2_cost,
        SUM(
            dc.total_cost * (lt.execution_time_in_seconds / lt.total_load_tasks_execution_time_in_seconds)
        ) AS individual_table_cost,
        SUM(lt.execution_time_in_seconds) AS execution_time_in_seconds,
        ANY_VALUE(lt.total_load_tasks_execution_time_in_seconds) AS total_load_tasks_execution_time_in_seconds,
        COUNT(*) AS total_runs_in_day,
        MIN(lt.ts_task_started) AS ts_min_task_started,
        MIN(lt.ts_task_ended) AS ts_min_task_ended,
        lt.year,
        lt.month,
        lt.day
    FROM
        load_tasks AS lt
    JOIN
        datalake_databricks.daily_clusters AS dc
            ON MAKE_DATE(lt.year, lt.month, lt.day) = dc.dt_cluster_run
            AND lt.id_cluster = dc.id_cluster
    WHERE
        lt.table_name IS NOT NULL
    GROUP BY
        lt.table_name,
        lt.year,
        lt.month,
        lt.day
),
indirect_costs AS (
    SELECT
        tdwi.dependent_table_name AS table_name,
        SUM(dc.individual_table_dbu_cost) AS indirect_table_dbu_cost,
        SUM(dc.individual_table_ec2_cost) AS indirect_table_ec2_cost,
        SUM(dc.individual_table_cost) AS indirect_table_cost,
        dc.year,
        dc.month,
        dc.day
    FROM
        datalake_databricks.bietlejuice_table_dependencies_with_indirection AS tdwi
    JOIN
        direct_costs AS dc
            ON dc.table_name = tdwi.dependency_table_name
            AND dc.year = tdwi.year
            AND dc.month = tdwi.month
            AND dc.day = tdwi.day
    GROUP BY
        tdwi.dependent_table_name,
        dc.year,
        dc.month,
        dc.day
)
SELECT
    dc.dag_name,
    dc.task_name,
    dc.table_name,
    dc.individual_table_dbu_cost,
    dc.individual_table_ec2_cost,
    dc.individual_table_cost,
    dc.individual_table_dbu_cost + COALESCE(ic.indirect_table_dbu_cost, 0) AS accumulated_table_dbu_cost,
    dc.individual_table_ec2_cost + COALESCE(ic.indirect_table_ec2_cost, 0) AS accumulated_table_ec2_cost,
    dc.individual_table_cost + COALESCE(ic.indirect_table_cost, 0) AS accumulated_table_cost,
    dc.execution_time_in_seconds,
    dc.total_runs_in_day,
    dc.ts_min_task_started,
    dc.ts_min_task_ended,
    dc.year,
    dc.month,
    dc.day
FROM
    direct_costs AS dc
LEFT JOIN
    indirect_costs AS ic
        ON dc.table_name = ic.table_name
        AND dc.year = ic.year
        AND dc.month = ic.month
        AND dc.day = ic.day
