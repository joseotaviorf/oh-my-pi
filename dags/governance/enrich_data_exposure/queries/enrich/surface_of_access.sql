WITH bietlejuice_tables AS (
    SELECT DISTINCT
        LOWER(table) AS table,
        year,
        month,
        day
    FROM
        datalake_dag_inventory_clean.table
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
),
filtered_daily_privileges AS (
    SELECT
        dtp.id_user,
        dtp.id_group,
        dtp.table_schema,
        dtp.table_name,
        dtp.grantee_type,
        dtp.year,
        dtp.month,
        dtp.day
    FROM
        datalake_databricks.daily_table_privileges AS dtp
    JOIN
        bietlejuice_tables AS bt
            ON bt.table = (dtp.table_schema || '.' || dtp.table_name)
    WHERE
        MAKE_DATE(dtp.year, dtp.month, dtp.day) BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
),
expanded_daily_privileges AS (
    SELECT
        id_user,
        table_schema,
        table_name,
        year,
        month,
        day
    FROM
        filtered_daily_privileges
    WHERE
        grantee_type = 'User'
    UNION
    SELECT
        dgm.id_user,
        tps.table_schema,
        tps.table_name,
        tps.year,
        tps.month,
        tps.day
    FROM
        filtered_daily_privileges AS tps
    JOIN
        datalake_databricks.daily_group_members AS dgm
            ON tps.id_group = dgm.id_group
            AND tps.year = dgm.year
            AND tps.month = dgm.month
            AND tps.day = dgm.day
    WHERE
        tps.grantee_type = 'Group'
        AND MAKE_DATE(dgm.year, dgm.month, dgm.day) BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
),
numerator AS (
    SELECT
        table_schema,
        table_name,
        COUNT(*) AS total_databricks_users_with_access,
        COUNT_IF(du.is_active_user) AS total_databricks_active_users_with_access,
        COUNT_IF(du.is_active_user AND du.is_active_employee) AS total_databricks_active_employees_with_access,
        edp.year,
        edp.month,
        edp.day
    FROM
        expanded_daily_privileges AS edp
    LEFT JOIN
        datalake_databricks.daily_users AS du
            ON edp.id_user = du.id_user
            AND edp.year = du.year
            AND edp.month = du.month
            AND edp.day = du.day
    GROUP BY
        table_schema,
        table_name,
        edp.year,
        edp.month,
        edp.day
),
denominator AS (
    SELECT
        COUNT(*) AS total_databricks_users,
        COUNT_IF(du.is_active_user) AS total_databricks_active_users,
        COUNT_IF(du.is_active_user AND du.is_active_employee) AS total_databricks_active_employees,
        du.year,
        du.month,
        du.day
    FROM
        datalake_databricks.daily_users AS du
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
    GROUP BY
        du.year,
        du.month,
        du.day
)
SELECT
    table_schema,
    table_name,
    total_databricks_users_with_access,
    total_databricks_users,
    total_databricks_active_users_with_access,
    total_databricks_active_users,
    total_databricks_active_employees_with_access,
    total_databricks_active_employees,
    year,
    month,
    day
FROM
    numerator
JOIN
    denominator
        USING(year, month, day)
