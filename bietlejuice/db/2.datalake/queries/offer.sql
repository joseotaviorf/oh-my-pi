select distinct
  eo.id,
  eo.atualizadoem,
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
;