with analysis_date as (
  select
    oa.id,
    min(cast(from_unixtime(cast(ure.timestamp as double) / 1000) as timestamp)) as _date
  from datalake_ebdb_raw_prod.offer_aud oa
  join datalake_ebdb_raw_prod.usuariorevisionentity ure
    on oa.rev = ure.id
  where oa.status_MOD = true
	and oa.status in ('Aprovada', 'Rejeitada')
  group by 1
),
rent_value_offers as (
  with max_date as (
    select
      id,
      turn,
      max(rev) as rev_
    from datalake_ebdb_raw_prod.offer_aud
    where turn_mod = true
      and type = 'Price'
    group by 1, 2
  )
  select
    o_aud.id,
    max(case when md.turn = 'Owner' then o_aud.rent end) as last_rent_offered_by_tenant,
	max(case when md.turn = 'Tenant' then o_aud.rent end) as last_rent_offered_by_owner
  from datalake_ebdb_raw_prod.offer_aud o_aud
  join max_date md
    on md.id = o_aud.id
      and md.rev_ = o_aud.rev
  group by 1
),
max_topic_type as (
  with max_topic_created as (
    select
      offer_id,
      max(id) as id
    from datalake_raw.godfather_topic
    group by 1
  )
  select gt.*
  from datalake_raw.godfather_topic gt
  join max_topic_created mtc
    on gt.offer_id = mtc.offer_id
      and gt.id = mtc.id
)
select distinct
  eo.id,
  eo.atualizadoem,
  ad._date as analysis_date,
  eo.criadoem,
  eo.firestoreid,
  eo.godfatherid,
  eo.originalcondo,
  eo.originalhomeinsurance,
  eo.originaliptu,
  eo.originalrent,
  eo.rent as last_offered_rent,
  eo.status,
  eo.turn,
  eo.client_id,
  eo.house_id,
  eo.rentflow_id,
  eo.rejectionreason,
  eo.iteration,
  eo.expirationdate,
  coalesce(go_godfather.type, go_firestore.type) as type,
  coalesce(go_godfather.first_sent_at, go_firestore.first_sent_at) as first_sent_at,
  coalesce(go_godfather.last_sent_at, go_firestore.last_sent_at) as last_sent_at,
  coalesce(mtt_godfather.type, mtt_firestore.type) as topic_type,
  rvo.last_rent_offered_by_tenant,
  rvo.last_rent_offered_by_owner
from datalake_ebdb_raw_prod.offer eo
left join datalake_raw.godfather_offer go_godfather
  on eo.godfatherid = try_cast(go_godfather.id as bigint)
    and eo.godfatherid is not null
left join datalake_raw.godfather_offer go_firestore
  on eo.firestoreid = go_firestore.firestore_id
    and eo.godfatherid is null
left join max_topic_type mtt_godfather
  on mtt_godfather.offer_id = go_godfather.id
left join max_topic_type mtt_firestore
  on mtt_firestore.offer_firestore_id = go_firestore.firestore_id
left join analysis_date ad
  on ad.id = eo.id
left join rent_value_offers rvo
  on rvo.id = eo.id
;