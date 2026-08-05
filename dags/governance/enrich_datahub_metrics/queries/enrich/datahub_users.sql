WITH all_employees AS (
  SELECT
    work_email,
    LOWER(work_email) AS work_email_lower,
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
  FROM datalake_people_public.org_chart
), datahub_users AS (
  SELECT DISTINCT
    /* ELEMENT_AT is 1-based on Databricks and EMR (equivalent to 0-based bracket [1]) */
    LOWER(ELEMENT_AT(SPLIT(id_user, 'urn:li:corpuser:'), 2)) AS user_email_lower
  FROM datalake_amplitude_clean.events
  WHERE
    id_app = '417002'
), databricks_users AS (
  SELECT DISTINCT
    LOWER(email) AS email_lower
  FROM datalake_databricks.unique_users
), trino_users AS (
  SELECT DISTINCT
    LOWER(session_user) AS session_user_lower
  FROM datalake_trino.query_usage_information
)
/* Force sort-merge joins: auto-broadcast of amplitude/trino DISTINCT sets OOMs / fails on EMR */
SELECT /*+ MERGE(dh) MERGE(db) MERGE(tr) */
  e.work_email AS user_email,
  e.area_class,
  e.job_class,
  e.business,
  e.product,
  e.vertical,
  e.line,
  e.chapter,
  e.assignment_status_type,
  CASE
    WHEN dh.user_email_lower IS NOT NULL THEN TRUE
    ELSE FALSE
  END AS is_datahub_user,
  CASE
    WHEN db.email_lower IS NOT NULL THEN TRUE
    ELSE FALSE
  END AS is_databricks_user,
  CASE
    WHEN tr.session_user_lower IS NOT NULL THEN TRUE
    ELSE FALSE
  END AS is_trino_user
FROM all_employees AS e
LEFT JOIN datahub_users AS dh
  ON e.work_email_lower = dh.user_email_lower
LEFT JOIN databricks_users AS db
  ON e.work_email_lower = db.email_lower
LEFT JOIN trino_users AS tr
  ON e.work_email_lower = tr.session_user_lower
