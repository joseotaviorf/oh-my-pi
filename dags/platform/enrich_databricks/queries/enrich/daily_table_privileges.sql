WITH table_privileges AS (
    SELECT
        grantee,
        table_schema,
        table_name,
        collect_set(privilege_type) AS privileges,
        'grant' as grant_type,
        inherited_from,
        case
          when inherited_from = 'CATALOG' then table_catalog
          when inherited_from = 'SCHEMA' then table_schema
          when inherited_from = 'NONE' then null
        end as inherited_object,
        -- We use current_date because the data in information_schema is always current
        -- We can't process historical data
        YEAR(CURRENT_DATE) AS year,
        MONTH(CURRENT_DATE) AS month,
        DAY(CURRENT_DATE) AS day
    FROM
        system.information_schema.table_privileges
    WHERE
        table_catalog = '{catalog}'
    GROUP BY ALL
    UNION
    SELECT
        table_owner AS grantee, -- The owner of the table has all privileges
        table_schema,
        table_name,
        array('ALL_PRIVILEGES') AS privileges,
        'table_owner' as grant_type,
        null as inherited_from,
        null as inherited_object,
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
    dsp.id_service_principal,
    tp.grantee,
    tp.privileges,
    CASE
        WHEN du.id_user IS NOT NULL THEN 'User'
        WHEN dg.id_group IS NOT NULL THEN 'Group'
        WHEN dsp.id_service_principal IS NOT NULL THEN 'Service principal'
        ELSE 'Service principal'
    END AS grantee_type,
    tp.grant_type,
    tp.table_schema,
    tp.table_name,
    tp.inherited_from,
    tp.inherited_object,
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
LEFT JOIN
    datalake_databricks.daily_service_principals AS dsp
        ON dsp.application_id = tp.grantee
        AND dsp.year = tp.year
        AND dsp.month = tp.month
        AND dsp.day = tp.day
