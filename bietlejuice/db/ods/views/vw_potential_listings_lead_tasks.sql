--drop view if exists vw_potential_listings_lead_tasks;
--create or replace view vw_potential_listings_lead_tasks as
-- first conversion task created for a lead
with base_lead_tasks_first AS (
    SELECT
        rn_lead.rep_id,
        rn_lead.lead_id,
        rn_lead.dt_created,
        rn_lead.dt_closed
    FROM rn_lead
    WHERE rn_first = 1
),
-- last conversion task created for a lead
base_lead_tasks_last AS (
  SELECT
      rn_lead.rep_id,
      rn_lead.lead_id,
      rn_lead.dt_created,
      rn_lead.dt_closed
  FROM rn_lead
  WHERE rn_last = 1
)
SELECT
    f.id,
    COALESCE(f.rep_id, btl.rep_id, '-1'::INTEGER) AS sk_user_sales_rep,
    COALESCE(btf.rep_id, '-1'::INTEGER) AS sk_user_first_task_assignee,
    COALESCE(btl.rep_id, '-1'::INTEGER) AS sk_user_last_task_assignee,
    COALESCE(TO_CHAR(CASE
                                    WHEN btf.dt_created < f.dt_lead THEN f.dt_lead
                                    ELSE btf.dt_created
                                END::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER
     ) AS sk_first_task_created_date,
    COALESCE(TO_CHAR(CASE
                                    WHEN btf.dt_closed < f.dt_lead THEN f.dt_lead
                                    ELSE btf.dt_closed
                                END::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER
     ) AS sk_first_task_closed_date,
    COALESCE(TO_CHAR(CASE
                                    WHEN btl.dt_created < f.dt_lead THEN f.dt_lead
                                    ELSE btl.dt_created
                                END::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER
     ) AS sk_last_task_created_date,
    COALESCE(TO_CHAR(CASE
                                    WHEN btl.dt_closed < f.dt_lead THEN f.dt_lead
                                    ELSE btl.dt_closed
                                END::DATE::TIMESTAMP WITH TIME ZONE, 'YYYYMMDD')::INTEGER, '-1'::INTEGER
     ) AS sk_last_task_closed_date,
    CASE
      WHEN btf.rep_id IS NOT NULL THEN 'Lead'
      WHEN COALESCE(bpt.house_id, f.rep_id) IS NOT NULL THEN 'Photojob'
      ELSE NULL
    END AS first_isales_intervention,
    COALESCE(f.isales_registrant_id, btf.rep_id) IS NOT NULL
    OR (bpt.has_job_photo = TRUE AND NOT f.is_self_service_photo_job_scheduled)
        AS has_isales_intervention,
    bpt.has_fup_photo AS has_fup_photo_task
  FROM listing_flows_with_reprocessed_leads AS f
  LEFT JOIN base_lead_tasks_first AS btf
    ON btf.lead_id = f.lead_id
  LEFT JOIN base_lead_tasks_last AS btl
    ON btl.lead_id = f.lead_id
  LEFT JOIN base_photo_tasks AS bpt
    ON f.imovel_id = bpt.house_id
