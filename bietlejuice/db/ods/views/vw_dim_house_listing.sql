drop view if exists vw_dim_house_listing;
create or replace view vw_dim_house_listing as
with b2b_info as (
  select distinct
    h.id as id_house,
    -- although these rules are replicated from vw_dim_lead, it would require much work to centralize with ODS right now
    -- TODO: after moving everything to our data lake, we can centralize rules like these ones
    coalesce(coalesce(lo.affiliate_type, l.affiliate_type) = 'B2BPartner' or pa_b2b.id is not null, false) as is_b2b,
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
),
special_conditions as (
  with special_conditions_prev as (
  -- filter multiple changes in a single day
  -- example:
  -- ----------------------------------------------------------------------------------------------------------------------------------
  -- |     id      |  special_condition_type  |       ts_opted_in      |       ts_opted_out      |    special_condition_status_mod    |
  -- ----------------------------------------------------------------------------------------------------------------------------------
  -- |    33713	   |       Exclusivity	      |   2019-04-24 21:01:08	 |           null          |                1 (opt-in)          | -> will be removed
  -- |    33713	   |       Exclusivity	      |   2019-04-24 21:01:08	 |    2019-04-24 21:01:10  |                1 (opt-out)         | -> will be removed
  -- |    33713	   |       Exclusivity	      |   2019-04-24 21:05:17	 |           null          |                1 (opt-in)          | -> will be removed
  -- |    33713	   |       Exclusivity	      |   2019-04-24 21:05:17	 |    2019-04-24 21:05:35  |                1 (opt-out)         |
  -- ----------------------------------------------------------------------------------------------------------------------------------
    select
      id,
      special_condition_type,
      date(ts_opted_in) as in_,
      max(date(ts_opted_out)) as out_
    from special_condition_aud
    where special_condition_status in ('OptedIn', 'OptedOut')
      and special_condition_type in ('Exclusivity', 'OriginalsReady', 'OriginalsReno')
    group by 1, 2, 3
  )
  select
    hsc.id_house,
    scp.special_condition_type,
    scp.in_,
    max(scp.out_) as out_
  from house_special_condition hsc
  join special_condition sc
    on id_special_condition = sc.id
  join special_conditions_prev scp
    on scp.id = sc.id
  group by 1, 2, 3
),
house_listings as (
  select
    ((h.id || '00') || coalesce(hl.version, 1))::bigint as sk_house_listing,
    h.id as id_house,
    h.id % 892700000 as short_id_house,
    hl.version as version,
    hl.status::varchar(255),
    hl.min_version_time as ts_listing_version_start,
    hl.max_version_time as ts_listing_version_end,
    h.data_primeiro_verificado as ts_house_registration_first_verification,
    h.last_confirmation_availability as ts_house_last_confirmation_availability,
    h.first_publication as ts_house_first_publication,
    h.ultima_publicacao as ts_house_last_publication,
    hl.min_version_time::date as ts_publication,
    hl.de_publication_date as ts_de_publication,
    hl.aluguel as rent,
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
    hl.start_version_category as listing_category_start,
    hl.end_version_category as listing_category_end,
    hl.is_last_version::integer::boolean,
    h.exclusivity::integer::boolean as is_exclusive,
    h.house_occupant as who_is_living,
    h.key_type,
    h.key_location,
    coalesce(h.visit_restriction = 'Restriction', false) as has_visit_restriction,
    h.predicted_price as house_predicted_price
  from house h
  left join house_listing hl
    on hl.id = h.id
),
listing_special_conditions as (
-- selecting the last time a listing had its special condition changed on its version
-- example:
-- ----------------------------------------------------------------------------------
-- |  sk_house_listing  |  special_condition_type  |  dt_opted_in  |  dt_opted_out  |
-- ----------------------------------------------------------------------------------
-- |    892812943001    |      OriginalsReady      |   2019-03-04  |   2019-05-12   | -> will be removed
-- |    892812943001    |      OriginalsReady      |   2019-05-13  |      null      |
-- ----------------------------------------------------------------------------------
  select
    hl.sk_house_listing,
    sc.special_condition_type,
    max(sc.in_) as dt_opted_in,
    max(sc.out_) as dt_opted_out
  from house_listings hl
  join special_conditions sc
    on hl.id_house = sc.id_house
      and greatest(sc.in_, hl.ts_listing_version_start::date) >= hl.ts_listing_version_start::date
      and greatest(sc.in_, hl.ts_listing_version_start::date) < coalesce(hl.ts_listing_version_end::date, (now() - interval '1 day')::date)
      and greatest(coalesce(sc.out_, (now() - interval '1 day')::date), coalesce(hl.ts_listing_version_end::date, (now() - interval '1 day')::date)) >= coalesce(hl.ts_listing_version_end::date, (now() - interval '1 day')::date)
      and greatest(coalesce(sc.out_, (now() - interval '1 day')::date), coalesce(hl.ts_listing_version_end::date, (now() - interval '1 day')::date)) >= hl.ts_listing_version_start::date
  group by 1, 2
),
listing_special_conditions_dates as (
	with multiple_special_conditions as (
	-- in case a house listing has more than one Special Condition types: exclusivity, ready and reno on the same version
  	  select
  		sk_house_listing,
  		special_condition_type,
  		dt_opted_in,
  		dt_opted_out,
  		-- selecting the maximum opt-in/out of a house listing, not considering the Originals' type
  		row_number() over (partition by sk_house_listing, special_condition_type order by dt_opted_in desc, coalesce(dt_opted_out, '2100-01-01'::date) desc) as rn_last,
  		row_number() over (partition by sk_house_listing, special_condition_type order by dt_opted_in asc, coalesce(dt_opted_out, '2100-01-01'::date) asc) as rn_first
  	  from listing_special_conditions
    ),
    last_opt as (
    -- select the latest Special Condition type a house listing has entered
      select
        sk_house_listing,
        special_condition_type,
        dt_opted_in,
        dt_opted_out
      from multiple_special_conditions
      where rn_last = 1
    ),
    first_opt as (
    -- select the latest Special Condition type a house listing has entered
      select
        sk_house_listing,
        special_condition_type,
        dt_opted_in,
        dt_opted_out
      from multiple_special_conditions
      where rn_first = 1
    )
     select
        fo.sk_house_listing,
        fo.special_condition_type,
        fo.dt_opted_in as dt_first_opted_in,
        fo.dt_opted_out as dt_first_opted_out,
        lo.dt_opted_in as dt_last_opted_in,
        lo.dt_opted_out as dt_last_opted_out
     from last_opt lo
     join first_opt fo
       on lo.sk_house_listing = fo.sk_house_listing and lo.special_condition_type = fo.special_condition_type
)
select
  hl.sk_house_listing,
  hl.id_house,
  hl.short_id_house,
  hl.version,
  hl.status,
  hl.ts_listing_version_start,
  hl.ts_listing_version_end,
  hl.ts_house_registration_first_verification,
  hl.ts_house_last_confirmation_availability,
  hl.ts_house_first_publication,
  hl.ts_house_last_publication,
  hl.ts_publication,
  hl.ts_de_publication,
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
  hl.listing_category_end,
  hl.is_last_version,
  lsc_exclusivity.dt_first_opted_in is not null as is_exclusive,
  hl.who_is_living,
  hl.key_type,
  hl.key_location,
  hl.has_visit_restriction,
  hl.house_predicted_price,
  bi.is_b2b,
  bi.b2b_type,
  bi.b2b_prime_type,
  lsc_originals.dt_last_opted_in is not null 
    and lsc_originals.dt_last_opted_out is null as is_originals_active,
  lsc_originals.special_condition_type as last_originals_type,
  lsc_originals.dt_last_opted_in as dt_last_originals_opted_in,
  lsc_originals.dt_last_opted_out as dt_last_originals_opted_out,
  lsc_exclusivity.dt_last_opted_out as dt_last_exclusive_opted_out,
  now() as ts_load
from house_listings hl
left join b2b_info bi
  on bi.id_house = hl.id_house
left join listing_special_conditions lsc_originals
  on hl.sk_house_listing = lsc_originals.sk_house_listing and lsc_originals.special_condition_type like 'Originals%'
left join listing_special_conditions lsc_exclusivity
  on hl.sk_house_listing = lsc_exclusivity.sk_house_listing and lsc_exclusivity.special_condition_type = 'Exclusivity'
;
