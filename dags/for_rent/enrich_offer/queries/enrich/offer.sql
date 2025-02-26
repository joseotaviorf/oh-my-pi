with analyzed_offers as (
    select
        oa.id_offer,
        min(ts_revision) as first_ts_revision
    from datalake_ebdb_clean.offer_aud oa
    join datalake_ebdb_user.user_revision_entity ure
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
            over (partition by offer.id_firestore) as id_offer_godfather,
        offer.id_firestore
    from datalake_ebdb_clean.offer
    left join datalake_godfather_clean.offer g_offer
        on offer.id_firestore = g_offer.id_firestore
        and offer.id_godfather is null
  ),
  instant_offer_firestore as (
      select distinct
        id_firestore,
        GET_JSON_OBJECT(resident, '$.people') AS number_of_tenants,
        GET_JSON_OBJECT(resident, '$.kids') AS number_of_kids,
        GET_JSON_OBJECT(tenant_intent, '$.rentalReason') AS rental_reason,
        GET_JSON_OBJECT(tenant_intent, '$.urgency') AS rental_urgency,
        GET_JSON_OBJECT(resident, '$.description') AS tenant_description,
        GET_JSON_OBJECT(resident, '$.petsInfo') AS tenant_pets_info,
        GET_JSON_OBJECT(resident, '$.members') AS tenant_type,
        type,
        GET_JSON_OBJECT(resident, '$.pets') AS has_pets,
        is_instant_offer,
        ts_email_sent_to_owner,
        ts_first_sent,
        ts_last_sent
      from datalake_firestore.rent_offer fo
      where status not in ('Draft','DismissedDraft')
  )
  select distinct
    o_firestore.id_offer,
    bo_godfather.id_firestore,
    bo_godfather.id,
    io_firestore.number_of_tenants,
    io_firestore.number_of_kids,
    io_firestore.rental_reason,
    io_firestore.rental_urgency,
    io_firestore.tenant_description,
    io_firestore.tenant_pets_info,
    io_firestore.tenant_type,
    io_firestore.type,
    io_firestore.has_pets,
    io_firestore.is_instant_offer,
    io_firestore.ts_email_sent_to_owner,
    COALESCE(bo_godfather.ts_first_sent, io_firestore.ts_first_sent) AS ts_first_sent,
    COALESCE(bo_godfather.ts_last_sent, io_firestore.ts_last_sent) AS ts_last_sent
  from offer_firestore o_firestore
  LEFT join datalake_godfather_clean.offer bo_godfather
    on bo_godfather.id = o_firestore.id_offer_godfather
  left join instant_offer_firestore io_firestore
    on o_firestore.id_firestore = io_firestore.id_firestore
)
select distinct
  offer.id,
  (offer.id * 100) + 2 as id_offer_context,
  offer.id_firestore,
  -- TODO [ODS] bug in Product attaching the same firestore id to different godfather entries
  max(coalesce(offer.id_godfather, firestore.id)) over (partition by offer.id_firestore) as id_godfather,
  hl.id_country,
  offer.id_client,
  offer.id_house,
  offer.id_rent_flow,
  hl.country_code,
  offer.original_condo,
  offer.original_home_insurance,
  offer.original_iptu,
  offer.original_rent,
  offer.status,
  offer.turn,
  offer.rejection_reason,
  offer.iteration,
  coalesce(firestore.type, bus_offer.type, offer.type) as type,
  offer.rent as last_offered_rent,
  negotiation.first_rent_offered_by_tenant,
  negotiation.first_rent_offered_by_owner,
  negotiation.last_rent_offered_by_tenant,
  negotiation.last_rent_offered_by_owner,
  firestore.number_of_tenants,
  firestore.number_of_kids,
  firestore.rental_reason,
  firestore.rental_urgency,
  firestore.tenant_description,
  firestore.tenant_pets_info,
  firestore.tenant_type,
  firestore.has_pets,
  coalesce(firestore.is_instant_offer, false) as is_instant_offer,
  coalesce(bus_offer.ts_last_sent, firestore.ts_last_sent) is not null as is_offer_submitted,
  firestore.ts_email_sent_to_owner,
  offer.ts_expired,
  analyzed.first_ts_revision as ts_analyzed,
  coalesce(bus_offer.ts_first_sent, firestore.ts_first_sent) as ts_first_sent,
  coalesce(bus_offer.ts_last_sent, firestore.ts_last_sent) as ts_last_sent,
  offer.ts_created,
  offer.ts_updated
from datalake_ebdb_clean.offer offer
left join analyzed_offers analyzed
  on analyzed.id_offer = offer.id
left join datalake_godfather_clean.offer bus_offer
  on offer.id_godfather = bus_offer.id
  and offer.id_godfather is not null
left join firestore_offers firestore
  on offer.id = firestore.id_offer
left join offer_negotiation negotiation
  on negotiation.id_offer = offer.id
JOIN
    datalake_ebdb_country.house AS hl
        ON hl.id_house = offer.id_house