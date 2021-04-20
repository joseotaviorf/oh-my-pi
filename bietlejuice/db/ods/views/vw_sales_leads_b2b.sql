--drop view if exists vw_sales_leads_b2b;
--create or replace view vw_sales_leads_b2b as
select distinct
    l.id as id_lead,
    pa_b2b_online.partner_id as online_partner_id
from
    public.lead l
left join
    public.partner_agent pa_b2b_online
        on pa_b2b_online.user_id = l.usuario_que_indicou_id
where
    pa_b2b_online.partner_id is not null
