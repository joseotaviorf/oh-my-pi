with approved_date as (
  select
    oa.id,
    min(cast(from_unixtime(cast(ure.timestamp as double) / 1000) as timestamp)) as _date
  from datalake_raw.ebdb_offer_aud oa
  join datalake_raw.ebdb_usuariorevisionentity ure
    on oa.rev = ure.id
  where oa.status_MOD = '1'
    and oa.status = 'Aprovada'
  group by 1
)
select distinct
  eo.id,
  eo.atualizadoem,
  ad._date as approved_date,
  eo.criadoem,
  eo.firestoreid,
  eo.godfatherid,
  eo.originalcondo,
  eo.originalhomeinsurance,
  eo.originaliptu,
  eo.originalrent,
  eo.rent,
  eo.status,
  eo.turn,
  eo.client_id,
  eo.house_id,
  eo.rentflow_id,
  eo.rejectionreason,
  eo.iteration,
  eo.expirationdate,
  go.type,
  go.first_sent_at,
  go.last_sent_at,
  gt.type as topic_type
from datalake_raw.ebdb_offer eo
join datalake_raw.godfather_offer go
  on eo.godfatherid = go.id
left join datalake_raw.godfather_topic gt
  on gt.offer_id = go.id
left join approved_date ad
  on ad.id = eo.id
;