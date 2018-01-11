drop table if exists unit_economics.tbl_base_ticket_task;
create table unit_economics.tbl_base_ticket_task as
with zendesk_groups as (
  select distinct
    id,
    case
      when trim("name") ~* '(adm financeiro)|(cx p.s)'
        then 'Customer Support (post-sale)'
      when trim("name") ~* '(comercial e afiliados)|(cx pr.)|(cx pr. missed chat)|(supporte)|(whatsapp)|(suporte$)'
        then 'Customer Support (pre-sale)'
      when trim("name") ~* '(adm casos)|(adm media..es)|(adm renova..o)|(adm rescis.o)'
        then 'mediacoes'
      when trim("name") ~* 'adm offboarding'
        then 'Back-Office (offboarding)'
      when trim("name") ~* '(adm onboarding)|(ongoing)'
        then 'Back-Office (onboarding)'
      when trim("name") ~* 'collections'
        then 'Collection'
      else lower(trim("name"))
    end as group_name
  from zendesk."group"
),
zendesk_ticket_fields as (
  select
    ticket_id,
    case
      when value ~* '0+' or value is null
        then '-1'
      else value
    end as value
  from zendesk.ticket_fields
  where id = '31646438' -- field id that maps a house id
),
zendesk_cte as (
  select distinct
    case
  	    when ztf.value = '-1' or ztf.value is null
  		    then coalesce(vbmu0.property_id::varchar, vbmu1.property_id::varchar, '-1')
        else ztf.value
    end as property_id,
    case
        when vbmu0.property_id is not null
        	then count(vbmu0.property_id)
        when vbmu1.property_id is not null
        	then count(vbmu1.property_id)
    	else count(ztf.value)
    end as qt,
    date_trunc('month', ztm.solved_at)::date as dt,
    zg.group_name
  from zendesk.ticket zt
    join zendesk_groups zg
      on zt.group_id = zg.id
    join zendesk.ticket_metrics ztm
      on zt.id = ztm.ticket_id
         and ztm.solved_at is not null
    left join zendesk_ticket_fields ztf
      on zt.id = ztf.ticket_id
    left join zendesk.user zu
      on zt.requester_id = zu.id
    left join unit_economics.vw_base_merged_users vbmu0
      on zu.email = vbmu0.email
    left join unit_economics.vw_base_merged_users vbmu1
      on regexp_replace(zu.phone, '^\+\d{2}|\D', '', 'g') = vbmu1.phone
  where zg.group_name in ('Customer Support (pre-sale)', 'Customer Support (post-sale)', 'Collection',
                            'Back-Office (onboarding)', 'Back-Office (offboarding)')
  group by ztf.value, vbmu0.property_id, vbmu1.property_id, zg.group_name, date_trunc('month', ztm.solved_at)::date
),
crm_tasks as (
  select
    coalesce(property_id::varchar, '-1') as property_id,
    date_trunc('month', performed_date)::date as performed_date,
    case
      when trim(workgroup_title) ~* ('ap.lices')
        then 'ongoing'
      when trim(workgroup_title) ~* ('(backstage)|(laudo vistoria)|(onboarding rental)')
        then 'Back-Office (onboarding)'
      when trim(workgroup_title) ~* ('(capta..o$)|(capta..o priorit.ria)')
        then 'inside sales'
      when trim(workgroup_title) ~* ('(confirma..o de visitas)|(confirmar sess.o de fotos)|(vistoria)|(lockbox)|(onboar.ing de visitas)')
        then 'field ops'
      when trim(workgroup_title) ~* ('(cr.dito)')
        then 'analise de credito'
      when trim(workgroup_title) ~* ('(minuta)|(negocia..o)')
        then 'closing'
      else lower(trim(workgroup_title))
    end as group_name
  from crm.tasks
  where workgroup_title is not null
  and performed_date is not null
),
crm_cte as (
  select
    property_id,
    count(property_id) as qt,
    performed_date as dt,
    group_name
  from crm_tasks
  where group_name = 'Back-Office (onboarding)'
  group by property_id, performed_date, group_name
),
result as (
  select
    coalesce(zendesk_cte.property_id, crm_cte.property_id) as property_id,
    coalesce(zendesk_cte.dt, crm_cte.dt) as dt,
    coalesce(zendesk_cte.qt, 0) + coalesce(crm_cte.qt, 0) as qt,
    coalesce(zendesk_cte.group_name, crm_cte.group_name) as group_name
  from zendesk_cte
  full outer join crm_cte
    on zendesk_cte.property_id = crm_cte.property_id
       and zendesk_cte.dt = crm_cte.dt
       and zendesk_cte.group_name = crm_cte.group_name
),
final_result as (
  select
    case
      when length(property_id) in (5,6)
        then 892700000 + property_id::integer
      when length(property_id) > 9 or property_id !~ '^8927'
        then -1
      else property_id::integer
    end as property_id,
    dt,
    qt,
    group_name
  from result
)
select
  property_id,
  dt,
  sum(qt) as qt,
  group_name
from final_result
group by property_id, dt, group_name
;