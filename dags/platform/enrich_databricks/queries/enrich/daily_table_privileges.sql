WITH table_privileges AS (
    SELECT
        grantee,
        table_schema,
        table_name,
        -- We use current_date because the data in information_schema is always current
        -- We can't process historical data
        YEAR(CURRENT_DATE) AS year,
        MONTH(CURRENT_DATE) AS month,
        DAY(CURRENT_DATE) AS day
    FROM
        system.information_schema.table_privileges
    WHERE
        privilege_type IN ('SELECT', 'ALL_PRIVILEGES')
        AND table_catalog = '{catalog}'
    UNION
    SELECT
        table_owner AS grantee, -- The owner of the table has all privileges
        table_schema,
        table_name,
        YEAR(CURRENT_DATE) AS year,
        MONTH(CURRENT_DATE) AS month,
        DAY(CURRENT_DATE) AS day
    FROM
        system.information_schema.tables
    WHERE
        table_catalog = '{catalog}'
)
SELECT
    du.id_user,
    dg.id_group,
    tp.grantee,
    CASE
        WHEN du.id_user IS NOT NULL THEN 'User'
        WHEN dg.id_group IS NOT NULL THEN 'Group'
        ELSE 'Service principal'
    END AS grantee_type,
    tp.table_schema,
    tp.table_name,
    tp.year,
    tp.month,
    tp.day
FROM
    table_privileges AS tp
LEFT JOIN
    datalake_databricks.daily_users AS du
        ON du.email = tp.grantee
        AND du.year = tp.year
        AND du.month = tp.month
        AND du.day = tp.day
LEFT JOIN
    datalake_databricks.daily_groups AS dg
        ON dg.display_name = tp.grantee
        AND dg.year = tp.year
        AND dg.month = tp.month
        AND dg.day = tp.day
