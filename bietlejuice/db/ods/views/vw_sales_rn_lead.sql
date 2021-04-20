--drop view if exists vw_sales_rn_lead;
--create or replace view vw_sales_rn_lead as
select
    lead_tasks.rep_id,
    lead_tasks.lead_id,
    lead_tasks.dt_created,
    lead_tasks.dt_closed,
    row_number() over (partition by lead_tasks.lead_id order by lead_tasks.dt_created asc) as rn_first,
    row_number() over (partition by lead_tasks.lead_id order by lead_tasks.dt_created desc) as rn_last
from
    crm.lead_tasks
