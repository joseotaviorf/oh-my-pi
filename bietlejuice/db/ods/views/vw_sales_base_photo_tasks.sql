--drop view if exists vw_sales_base_photo_tasks;
--create or replace view vw_sales_base_photo_tasks as
select distinct
    coalesce(h.id, h_direct.id)::integer as house_id,
    max((task_type = 'AgendarJobDeFotografo')::integer)::boolean as has_job_photo,
    max((task_type = 'FupFoto')::integer)::boolean as has_fup_photo
from
    crm.photo_tasks pt
left join
    public.photo_job pj
        on pt.origin_id = pj.id
left join
    public.house h
        on h.id = pj.imovel_id
left join
    public.house h_direct
        on h_direct.id = pt.origin_id
where
    coalesce(h.id, h_direct.id) is not null
group by 1
