drop view if exists vw_dim_house_listing;
create or replace view vw_dim_house_listing as
with b2b_info as (
  select distinct
    h.id as id_house,
    -- although these rules are replicated from vw_dim_lead, it would require much work to centralize with ODS right now
    -- TODO: after moving everything to our data lake, we can centralize rules like these ones
    coalesce(coalesce(lo.affiliate_type, l.affiliate_type) = 'B2BPartner' 
      or pa_b2b.id is not null
      , false) as is_b2b,
    case
      when coalesce(lo.affiliate_type, l.affiliate_type) = 'B2BPartner'
        then 'online'
      when pa_b2b.id is not null
        then 'prime'
    end as b2b_type,
    case
    -- because a lead can have both 'affiliate_type' = 'B2BPartner' and 'partner_agent.id' not null and we need to
    -- prioritize the first type (online), the following check must be done
      when pa_b2b.id is not null and coalesce(lo.affiliate_type, l.affiliate_type, '') != 'B2BPartner'
        then
          case
            when pj.id is null and h.first_publication is not null
              then 'advanced_negotiation'
            when h.external_id is null or h.external_id ~ '^([a-zA-Z0-9]+-){4}[a-zA-Z0-9]+$'
              then 'standard'
            when h.external_id is not null
              then 'batch'
          end
    end as b2b_prime_type
  from house h
  left join lead_conversion lc
    on lc.id_house = h.id
  left join lead l
    on l.id = lc.id_lead
  left join reprocessed_lead rl
    on rl.id = l.id
  left join lead lo
    on lo.id = rl.id_origin_lead
  left join partner_agent pa_b2b
    on pa_b2b.user_id = h.usuario_id
  left join house_listing hl
    on h.id = hl.id_house
  left join photo_job pj
    on pj.imovel_id = h.id
    and pj.dt_job_created between hl.ts_listing_version_start and hl.ts_listing_version_end
),
house_portability as (
    select
        hl.id_house_listing
    from house_listing hl
    join house h
        on h.id = hl.id_house
    join portability por
        on por.id_house = hl.id_house and por.owner_type = 'B2B'
    where por.ts_created between coalesce(hl.ts_listing_version_start, '1900-01-01 00:00:00') and coalesce(hl.ts_listing_version_end, now())
),
house_listings as (
  with lbc as (
    select
       id_house,
       max((business_context = 'SALE')::integer)::boolean as is_for_sale,
       max((business_context = 'RENT')::integer)::boolean as is_for_rent
    from
       listing_business_context
    group by 1
  )
  select
    hl.id_house_listing as sk_house_listing,
    h.id as id_house,
    h.id % 892700000 as short_id_house,
    hl.version,
    hl.status::varchar(255),
    hl.ts_listing_version_start,
    hl.ts_listing_version_end,
    h.first_publication as ts_house_first_publication,
    h.ultima_publicacao as ts_house_last_publication,
    hl.ts_listing_version_start::date as ts_publication,
    hl.ts_last_de_publication,
    hl.rent,
    h.aluguel as house_rent,
    h.bairro as house_neighborhood,
    h.cep as house_zipcode,
    h.cidade as house_city,
    h.complemento as house_complement,
    h.condominio as house_condo,
    h.elevador as house_elevator,
    h.endereco as house_address,
    h.iptu as house_iptu,
    h.lat as house_lat,
    h.lng as house_lng,
    h.mobiliado::boolean as is_house_furnished,
    h.numero as house_number,
    h.numero_banheiros as house_bathrooms,
    h.numero_quartos as house_bedrooms,
    h.numero_suites as house_suites,
    h.numero_vagas as house_garages,
    h.status as house_status,
    h.tipo as house_type,
    h.tipo_porteiro as house_entrance,
    h.tipo_vagas as house_garage_type,
    h.verificado::boolean as is_house_registration_verified,
    h.valor_total as house_total_value,
    h.area_total as house_total_area,
    h.area_terreno as house_construction_area,
    h.tipo_condominio as house_condo_type,
    h.tipo_iptu as house_iptu_type,
    h.data_criacao as ts_house_create,
    h.atualizado_em as ts_house_update,
    h.registration_abandoned_reason as registration_abandoned_reason,
    h.unpublished_reason as house_unpublished_reason,
    hl.listing_category_start,
    hl.is_last_version,
    hl.is_exclusive,
    h.house_occupant as who_is_living,
    h.key_type,
    h.key_location,
    coalesce(h.visit_restriction = 'Restriction', false) as has_visit_restriction,
    h.predicted_price as house_predicted_price,
    hl.dt_last_exclusive_opted_in,
    hl.dt_last_exclusive_opted_out,
    hl.is_originals_active,
    hl.last_originals_type,
    hl.dt_last_originals_opted_in,
    hl.dt_last_originals_opted_out,
    hl.is_iorent_active,
    hl.last_iorent_type,
    hl.dt_last_iorent_opted_in,
    hl.dt_last_iorent_opted_out,
    h.sale_price,
    case
       when lbc.id_house is null then true -- When house is not in listing_business_context, it is for rent
       else coalesce(lbc.is_for_rent, false)
    end as is_for_rent,
    coalesce(lbc.is_for_sale, false) as is_for_sale,
    h.has_instant_offer_enabled
  from house h
  join house_listing hl
    on hl.id_house = h.id
  left join lbc
    on lbc.id_house = h.id
)
select
  hl.sk_house_listing,
  hl.id_house,
  hl.short_id_house,
  hl.version,
  hl.status,
  hl.ts_listing_version_start,
  hl.ts_listing_version_end,
  hl.ts_house_first_publication,
  hl.ts_house_last_publication,
  hl.ts_publication,
  hl.ts_last_de_publication,
  hl.rent,
  hl.house_rent,
  hl.house_neighborhood,
  hl.house_zipcode,
  hl.house_city,
  hl.house_complement,
  hl.house_condo,
  hl.house_elevator,
  hl.house_address,
  hl.house_iptu,
  hl.house_lat,
  hl.house_lng,
  hl.is_house_furnished,
  hl.house_number,
  hl.house_bathrooms,
  hl.house_bedrooms,
  hl.house_suites,
  hl.house_garages,
  hl.house_status,
  hl.house_type,
  hl.house_entrance,
  hl.house_garage_type,
  hl.is_house_registration_verified,
  hl.house_total_value,
  hl.house_total_area,
  hl.house_construction_area,
  hl.house_condo_type,
  hl.house_iptu_type,
  hl.ts_house_create,
  hl.ts_house_update,
  hl.registration_abandoned_reason,
  hl.house_unpublished_reason,
  hl.listing_category_start,
  hl.is_last_version,
  hl.is_exclusive,
  hl.dt_last_exclusive_opted_in,
  hl.dt_last_exclusive_opted_out,
  hl.who_is_living,
  hl.key_type,
  hl.key_location,
  hl.has_visit_restriction,
  hl.house_predicted_price,
  (bi.is_b2b or hp.id_house_listing is not null) as is_b2b,
  bi.b2b_type,
  case
      when hp.id_house_listing is not null then 'portability'
      else bi.b2b_prime_type
  end as b2b_prime_type,
  hl.is_originals_active,
  hl.last_originals_type,
  hl.dt_last_originals_opted_in,
  hl.dt_last_originals_opted_out,
  hl.is_iorent_active,
  hl.last_iorent_type,
  hl.dt_last_iorent_opted_in,
  hl.dt_last_iorent_opted_out,
  hl.sale_price,
  hl.is_for_rent,
  hl.is_for_sale,
  hl.has_instant_offer_enabled,
  now() as ts_load
from house_listings hl
left join b2b_info bi
  on bi.id_house = hl.id_house
left join house_portability hp
    on hp.id_house_listing = hl.sk_house_listing
;