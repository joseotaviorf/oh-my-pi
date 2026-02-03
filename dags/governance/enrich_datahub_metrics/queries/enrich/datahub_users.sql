WITH 
    all_employees AS (
    SELECT 
        work_email,
        job_class,
        business,
        product,
        vertical,
        line,
        chapter,
        assignment_status_type,
        CASE
            WHEN chapter = 'Data' OR directorate = 'Dados' THEN 'Tech - Data'
            ELSE COALESCE(vertical, 'Corp')
        END AS area_class
    FROM 
        datalake_people_public.org_chart
),
datahub_users AS (
    SELECT DISTINCT 
        split(id_user, 'urn:li:corpuser:')[1] AS user_email
    FROM 
        datalake_amplitude_clean.events 
    WHERE 
        id_app = '417002' 
),
databricks_users AS (
    SELECT DISTINCT 
        email 
    FROM 
        datalake_databricks.unique_users 
),
trino_users AS (
    SELECT DISTINCT 
        session_user
    FROM 
        datalake_trino.query_usage_information 
)
SELECT
    COALESCE(e.work_email, dh.user_email) AS user_email,
    e.area_class,
    e.job_class,
    e.business,
    e.product,
    e.vertical,
    e.line,
    e.chapter,
    e.assignment_status_type,    
    CASE 
        WHEN dh.user_email IS NOT NULL THEN TRUE 
        ELSE FALSE 
    END AS is_datahub_user,
    CASE
        WHEN db.email IS NOT NULL THEN TRUE 
        ELSE FALSE 
    END AS is_databricks_user,
    CASE 
        WHEN tr.session_user IS NOT NULL THEN TRUE 
        ELSE FALSE 
    END AS is_trino_user
FROM all_employees e
LEFT JOIN datahub_users dh ON LOWER(e.work_email) = LOWER(dh.user_email)
LEFT JOIN databricks_users db ON LOWER(e.work_email) = LOWER(db.email)
LEFT JOIN trino_users tr ON LOWER(e.work_email) = LOWER(tr.session_user)