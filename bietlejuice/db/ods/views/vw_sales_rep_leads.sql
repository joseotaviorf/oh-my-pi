--drop view if exists vw_sales_rep_leads;
--create or replace view vw_sales_rep_leads as
with base_leads as (
  select
    lead.id as lead_id,
    lead.tipo as lead_type,
    lead.origem as lead_origin,
    lead.utm_source,
    lead.utm_medium,
    coalesce(lower(btrim(lead.utm_campaign)) ~* '(institucional)|(branded)' and lower(btrim(lead.utm_campaign)) !~* '(non-branded)', false) as branded_lead,
    lead.codigo_imobiliaria is not null OR lead.flg_b2b as b2b_lead,
    case when lead.origem = 'Reprocessado'
    	then rl.id_origin_lead
    	else null
    end as old_lead_id
  from lead
  	left join reprocessed_lead rl on rl.id = lead.id
)
select
  bl.lead_id,
  coalesce(old_bl.lead_type, bl.lead_type) as lead_type,
  coalesce(old_bl.lead_origin, bl.lead_origin) as lead_origin,
  coalesce(old_bl.utm_source, bl.utm_source) as utm_source,
  coalesce(old_bl.utm_medium, bl.utm_medium) as utm_medium,
  coalesce(old_bl.branded_lead, bl.branded_lead) as branded_lead,
  coalesce(old_bl.b2b_lead, bl.b2b_lead) as b2b_lead,
  coalesce(bl.lead_origin = 'Reprocessado', false) as reprocessed_flg
from base_leads bl
left join base_leads old_bl
  on old_bl.lead_id = bl.old_lead_id
