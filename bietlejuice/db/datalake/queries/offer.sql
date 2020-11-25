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
min_max_date as (
    select
      id,
      turn,
      max(rev) as max_rev,
      min(rev) as min_rev
    from datalake_ebdb_raw_prod.offer_aud as oa
    group by 1, 2
), 
rent_value_offers as (
  select 
    o_aud.id, 
    min(case when mnd.turn = 'Owner' and mnd.min_rev is not null then o_aud.rent end) as first_rent_offered_by_tenant,
    min(case when mnd.turn = 'Tenant' and mnd.min_rev is  not null then o_aud.rent end) as first_rent_offered_by_owner,
    max(case when mxd.turn = 'Owner' and mxd.max_rev is not null then o_aud.rent end) as last_rent_offered_by_tenant,
    max(case when mxd.turn = 'Tenant' and mxd.max_rev is  not null then o_aud.rent end) as last_rent_offered_by_owner 
  from datalake_ebdb_raw_prod.offer_aud o_aud
  left join min_max_date mxd
    on mxd.id = o_aud.id
    and mxd.max_rev = o_aud.rev
  left join min_max_date mnd
    on mnd.id = o_aud.id
      and mnd.min_rev = o_aud.rev
  group by 1  
),
firestore_offers as (
  with offer_firestore as (
    select
      eo.id as id_offer,
      max(coalesce(eo.godfatherid, try_cast(go_firestore.id as bigint))) over (partition by eo.firestoreid) as godfatherid
    from datalake_ebdb_raw_prod.offer eo
    left join datalake_godfather_clean_prod.business_offer go_firestore
      on eo.firestoreid = go_firestore.id_firestore
        and eo.godfatherid is null
  ),
  instantoffer_firestore as (
      select
        id_firestore,
        is_instant_offer
      from datalake_firestore_prod.rent_offer fo
      where status not in ('Draft','DismissedDraft')
  )
  select
    offer_firestore.id_offer,
    go_firestore.id_firestore,
    go_firestore.id,
    go_firestore.ts_first_sent,
    go_firestore.ts_last_sent,
    go_firestore.type as distinct_type,
    fo.is_instant_offer
  from offer_firestore
  join datalake_godfather_clean_prod.business_offer go_firestore
    on go_firestore.id = godfatherid
  left join instantoffer_firestore fo
    on go_firestore.id_firestore = fo.id_firestore
  group by 1, 2, 3, 4, 5, 6, 7
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
  coalesce(go_godfather.type, go_firestore.distinct_type) as type,
  coalesce(go_godfather.ts_first_sent, go_firestore.ts_first_sent) as first_sent_at,
  coalesce(go_godfather.ts_last_sent, go_firestore.ts_last_sent) as last_sent_at,
  rvo.first_rent_offered_by_tenant,
  rvo.first_rent_offered_by_owner,
  rvo.last_rent_offered_by_tenant,
  rvo.last_rent_offered_by_owner,
  coalesce(go_firestore.is_instant_offer, false) as is_instant_offer
from datalake_ebdb_raw_prod.offer eo
left join datalake_godfather_clean_prod.business_offer go_godfather
  on eo.godfatherid = try_cast(go_godfather.id as bigint)
    and eo.godfatherid is not null
left join firestore_offers go_firestore
  on eo.id = go_firestore.id_offer
left join analysis_date ad
  on ad.id = eo.id
left join rent_value_offers rvo
  on rvo.id = eo.id
;
