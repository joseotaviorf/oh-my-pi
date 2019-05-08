drop view if exists vw_dim_house_listing;
create or replace view vw_dim_house_listing as
with b2b_info as (
  select
    h.id as id_house,
    -- although these rules are replicated from vw_dim_lead, it would much work to centralize with ODS right now
    -- TODO: after moving everything to our data lake, we can centralize rules like these ones
    coalesce(coalesce(lo.affiliate_type, l.affiliate_type) = 'B2BPartner', pa_b2b.id is not null) as is_b2b,
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
            when pj.id is null
              then 'advanced_negotiation'
            when h.external_id is null
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
  left join photo_job pj
    on pj.imovel_id = h.id
)
select
  ((h.id || '00') || coalesce(pl.version, 1))::bigint as sk_house_listing,
  h.id as id_house,
  h.id % 892700000 as short_id_house,
  pl.version as version,
  pl.status::varchar(255),
  pl.min_version_time as ts_listing_version_start,
  pl.max_version_time as ts_listing_version_end,
  h.data_primeiro_verificado as ts_house_registration_first_verification,
  h.last_confirmation_availability as ts_house_last_confirmation_availability,
  h.first_publication as ts_house_first_publication,
  h.ultima_publicacao as ts_house_last_publication,
  pl.min_version_time::date as ts_publication,
  pl.de_publication_date as ts_de_publication,
  pl.aluguel as rent,
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
  pl.start_version_category as listing_category_start,
  pl.end_version_category as listing_category_end,
  pl.is_last_version::integer::boolean,
  h.exclusivity::integer::boolean as is_exclusive,
  h.house_occupant as who_is_living,
  h.key_type,
  h.key_location,
  coalesce(h.visit_restriction = 'Restriction', false) as has_visit_restriction,
  h.predicted_price as house_predicted_price,
  bi.is_b2b,
  bi.b2b_type,
  bi.b2b_prime_type,
  now() as ts_load
from house h
left join house_listing pl
  on pl.id = h.id
left join b2b_info bi
  on bi.id_house = h.id
