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
 with min_max_date as (
    select
      id,
      turn,
      max(rev) as max_rev,
      min(rev) as min_rev
    from datalake_ebdb_raw_prod.offer_aud
    where
    turn_mod = true and (type = 'Price' or (type = 'Custom' and originalrent != rent))
    group by 1, 2
  )
  select
    o_aud.id,
    min(case when mnd.turn = 'Owner' and o_aud.iteration = 2 then o_aud.rent end) as first_rent_offered_by_tenant,
  min(case when mnd.turn = 'Tenant' and o_aud.iteration = 3 then o_aud.rent end) as first_rent_offered_by_owner,
    max(case when mxd.turn = 'Owner' then o_aud.rent end) as last_rent_offered_by_tenant,
  max(case when mxd.turn = 'Tenant'then o_aud.rent end) as last_rent_offered_by_owner
  from datalake_ebdb_raw_prod.offer_aud o_aud
  left join min_max_date mxd
    on mxd.id = o_aud.id
    and mxd.max_rev = o_aud.rev
  left join min_max_date mnd
    on mnd.id = o_aud.id
      and mnd.min_rev = o_aud.rev
  where o_aud.type != 'Express'
  group by 1
),
max_topic_type as (
  with max_topic_created as (
    select
      id_offer,
      max(id) as id
    from datalake_godfather_clean_prod.business_topic
    group by 1
  )
  select gt.*
  from datalake_godfather_clean_prod.business_topic gt
  join max_topic_created mtc
    on gt.id_offer = mtc.id_offer
      and gt.id = mtc.id
)
select distinct
  eo.id,
  eo.atualizadoem,
  ad._date as analysis_date,
  eo.criadoem,
  eo.firestoreid,
  -- FIXME: bug in Product attaching the same firestore id to different godfather entries
  max(coalesce(eo.godfatherid, try_cast(go_firestore.id as bigint))) over (partition by eo.firestoreid) as godfatherid,
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
  coalesce(go_godfather.ts_first_sent, go_firestore.ts_first_sent) as first_sent_at,
  coalesce(go_godfather.ts_last_sent, go_firestore.ts_last_sent) as last_sent_at,
  coalesce(mtt_godfather.type, mtt_firestore.type) as topic_type,
  rvo.first_rent_offered_by_tenant,
  rvo.first_rent_offered_by_owner,
  rvo.last_rent_offered_by_tenant,
  rvo.last_rent_offered_by_owner
from datalake_ebdb_raw_prod.offer eo
left join datalake_godfather_clean_prod.business_offer go_godfather
  on eo.godfatherid = try_cast(go_godfather.id as bigint)
    and eo.godfatherid is not null
left join datalake_godfather_clean_prod.business_offer go_firestore
  on eo.firestoreid = go_firestore.id_firestore
    and eo.godfatherid is null
left join max_topic_type mtt_godfather
  on mtt_godfather.id_offer = go_godfather.id
left join max_topic_type mtt_firestore
  on mtt_firestore.id_offer_firestore = go_firestore.id_firestore
left join analysis_date ad
  on ad.id = eo.id
left join rent_value_offers rvo
  on rvo.id = eo.id
;
