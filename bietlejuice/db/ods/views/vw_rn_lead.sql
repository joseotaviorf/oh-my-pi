--drop view if exists vw_rn_lead;
--create or replace view vw_rn_lead as
SELECT
  lead_tasks.rep_id,
  lead_tasks.lead_id,
  lead_tasks.dt_created,
  lead_tasks.dt_closed,
  ROW_NUMBER() OVER (PARTITION BY lead_tasks.lead_id ORDER BY lead_tasks.dt_created ASC) AS rn_first,
  ROW_NUMBER() OVER (PARTITION BY lead_tasks.lead_id ORDER BY lead_tasks.dt_created DESC) AS rn_last
FROM crm.lead_tasks
