-- first conversion task created for a lead
with base_lead_tasks_first AS (
    SELECT
        id_rep,
        id_lead,
        ts_created,
        ts_closed
    FROM datalake_crm_lead.lead_tasks
    WHERE lead_task_order = 1
),
-- last conversion task created for a lead
base_lead_tasks_last AS (
  SELECT
      id_rep,
      id_lead,
      ts_created,
      ts_closed
  FROM datalake_crm_lead.lead_tasks
  WHERE lead_task_inverse_order = 1
)
SELECT
    listing_flow.id,
    COALESCE(listing_flow.id_rep, btl.id_rep, CAST(-1 AS INTEGER)) AS id_user_sales_rep,
    COALESCE(btf.id_rep, CAST(-1 AS INTEGER)) AS id_user_first_task_assignee,
    COALESCE(btl.id_rep, CAST(-1 AS INTEGER)) AS id_user_last_task_assignee,
    CASE
        WHEN btf.id_rep IS NOT NULL THEN 'Lead'
        WHEN COALESCE(photo_tasks.id_house, listing_flow.id_rep) IS NOT NULL THEN 'Photojob'
        ELSE NULL
    END AS first_isales_intervention,
    CASE
        WHEN btf.ts_created < listing_flow.ts_lead
            THEN DATE(listing_flow.ts_lead)
        ELSE DATE(btf.ts_created)
        END AS dt_first_task_created_date,
    CASE
        WHEN btf.ts_closed < listing_flow.ts_lead
            THEN DATE(listing_flow.ts_lead)
        ELSE DATE(btf.ts_closed)
        END AS dt_first_task_closed_date,
    CASE
        WHEN btl.ts_created < listing_flow.ts_lead
            THEN DATE(listing_flow.ts_lead)
        ELSE DATE(btl.ts_created)
        END AS dt_last_task_created_date,
    CASE
        WHEN btl.ts_closed < listing_flow.ts_lead
            THEN DATE(listing_flow.ts_lead)
        ELSE DATE(btl.ts_closed)
        END AS dt_last_task_closed_date,
    COALESCE(listing_flow.id_isales_registrant, btf.id_rep) IS NOT NULL
        OR (photo_tasks.has_job_photo
            AND NOT listing_flow.is_self_service_photo_job_scheduled)
        AS has_isales_intervention,
    photo_tasks.has_fup_photo AS has_fup_photo_task
FROM datalake_listing_flow.listing_flows_with_reprocessed_leads AS listing_flow
LEFT JOIN base_lead_tasks_first AS btf
    ON btf.id_lead = listing_flow.id_lead
LEFT JOIN base_lead_tasks_last AS btl
    ON btl.id_lead = listing_flow.id_lead
LEFT JOIN datalake_listing_jobs.house_photo_job_tasks AS photo_tasks
    ON listing_flow.id_house = photo_tasks.id_house