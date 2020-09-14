with analyzed_offers as (
    select
        oa.id_offer,
        min(ts_revision) as first_ts_revision
    from datalake_ebdb_clean.offer_aud oa
    join datalake_ebdb_user_revision_entity.user_revision_entity ure
        on oa.rev = ure.id
    where oa.mod_status
        and oa.status in ('Aprovada', 'Rejeitada')
    group by 1
),
offer_negotiation as (
    with offer_min_max_aud as (
        select
          id_offer,
          turn,
          max(rev) as max_rev,
          min(rev) as min_rev
        from datalake_ebdb_clean.offer_aud as oa
        group by 1, 2
    )
    select
        o_aud.id_offer,
        min(
            if(
                offer_min_aud.turn = 'Owner'
                   and offer_min_aud.min_rev is not null,
                o_aud.rent,
                null
             )
        ) as first_rent_offered_by_tenant,
        min(
            if(
                offer_min_aud.turn = 'Tenant'
                    and offer_min_aud.min_rev is not null,
                o_aud.rent,
                null
            )
        ) as first_rent_offered_by_owner,
        max(
            if(
                offer_max_aud.turn = 'Owner'
                    and offer_max_aud.max_rev is not null,
                o_aud.rent,
                null
            )
        ) as last_rent_offered_by_tenant,
        max(
            if(
                offer_max_aud.turn = 'Tenant'
                    and offer_max_aud.max_rev is not null,
                o_aud.rent,
                 null
            )
        ) as last_rent_offered_by_owner
    from datalake_ebdb_clean.offer_aud o_aud
    left join offer_min_max_aud offer_max_aud
        on offer_max_aud.id_offer = o_aud.id_offer
        and offer_max_aud.max_rev = o_aud.rev
    left join offer_min_max_aud offer_min_aud
        on offer_min_aud.id_offer = o_aud.id_offer
        and offer_min_aud.min_rev = o_aud.rev
    group by 1
),
firestore_offers as (
  with offer_firestore as (
    select
        offer.id as id_offer,
        max(coalesce(offer.id_godfather, g_offer.id))
            over (partition by offer.id_firestore) as id_offer_godfather
    from datalake_ebdb_clean.offer
    left join datalake_godfather_clean.business_offer g_offer
        on offer.id_firestore = g_offer.id_firestore
        and offer.id_godfather is null
  ),
  instant_offer_firestore as (
    with offers_ranked as (
      select distinct
        id_firestore,
        is_instant_offer,
        rank() over (partition by id_firestore order by ts_last_sent desc) as ranking
      from datalake_firestore_clean.offers fo
      where status not in ('Draft','DismissedDraft')
    )
    select
      id_firestore,
      is_instant_offer
    from offers_ranked
    where ranking = 1
  )
  select distinct
    o_firestore.id_offer,
    bo_godfather.id_firestore,
    bo_godfather.id,
    bo_godfather.ts_first_sent,
    bo_godfather.ts_last_sent,
    bo_godfather.type,
    io_firestore.is_instant_offer
  from offer_firestore o_firestore
  join datalake_godfather_clean.business_offer bo_godfather
    on bo_godfather.id = o_firestore.id_offer_godfather
  left join instant_offer_firestore io_firestore
    on bo_godfather.id_firestore = io_firestore.id_firestore
)
select distinct
  offer.id,
  offer.id_firestore,
  -- TODO [ODS] bug in Product attaching the same firestore id to different godfather entries
  max(coalesce(offer.id_godfather, firestore.id)) over (partition by offer.id_firestore) as id_godfather,
  offer.id_client,
  offer.id_house,
  offer.id_rent_flow,
  offer.original_condo,
  offer.original_home_insurance,
  offer.original_iptu,
  offer.original_rent,
  offer.status,
  offer.turn,
  offer.rejection_reason,
  offer.iteration,
  coalesce(bus_offer.type, firestore.type) as type,
  offer.rent as last_offered_rent,
  negotiation.first_rent_offered_by_tenant,
  negotiation.first_rent_offered_by_owner,
  negotiation.last_rent_offered_by_tenant,
  negotiation.last_rent_offered_by_owner,
  firestore.is_instant_offer,
  coalesce(bus_offer.ts_last_sent, firestore.ts_last_sent) is not null as is_offer_submitted,
  offer.ts_expired,
  analyzed.first_ts_revision as ts_analyzed,
  coalesce(bus_offer.ts_first_sent, firestore.ts_first_sent) as ts_first_sent,
  coalesce(bus_offer.ts_last_sent, firestore.ts_last_sent) as ts_last_sent,
  offer.ts_created,
  offer.ts_updated
from datalake_ebdb_clean.offer offer
left join analyzed_offers analyzed
  on analyzed.id_offer = offer.id
left join datalake_godfather_clean.business_offer bus_offer
  on offer.id_godfather = bus_offer.id
  and offer.id_godfather is not null
left join firestore_offers firestore
  on offer.id = firestore.id_offer
left join offer_negotiation negotiation
  on negotiation.id_offer = offer.id
