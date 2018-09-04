select
  coalesce(trim(ctr.id) || date_format(cast(ctr.dt_start as timestamp), '%Y%m%d%H%i%S'), '-1') as sk_visit_task,
  coalesce(cast(coalesce(fdv.ods_id, fdh.ods_id) as bigint), -1) as sk_demand,
  now() as dt_timestamp
from datalake_clean.crm_tasks_resolution ctr
full outer join datalake_clean.ods_fact_demand fdv
  on cast(fdv.sk_booking as bigint) = cast(ctr.id_origin as bigint)
    and trim(ctr.type) = 'ConfirmarAgendamento'
    and trim(ctr.origin) = 'Agendamento'
full outer join datalake_clean.ods_fact_demand fdh
  on cast(substr(fdh.sk_house, 1, 9) as bigint) = cast(ctr.id_origin as bigint)
    and trim(ctr.type) = 'ConfirmarCondicoesEntrada'
    and trim(ctr.origin) = 'Imovel'
group by 1, 2 -- needed because of possible multiple lines in fact_demand due to offers, proposals and contracts
;