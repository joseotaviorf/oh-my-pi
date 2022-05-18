with special_condition as (
  -- there is a known bug that creates multiple rows for some houses
  select
    hsc.id_house,
    max(hsc.id_special_condition is not null) as is_exclusive
  from datalake_ebdb_clean.house_special_condition hsc
  join
    datalake_ebdb_clean.special_condition sc
      on sc.id = hsc.id_special_condition
      and sc.special_condition_type = 'Exclusivity'
      and sc.special_condition_status in ('OptedIn', 'Applied')
  group by 1
),
visit_info as (
  select
    id_house,
    max(visit_information='AUTORIZACAO_DE_ENTRADA') as has_entry_authorization,
    max(visit_information='PROPRIETARIO_ACOMPANHA') as is_owner_joinning,
    max(visit_information='ESTAMOS_LIBERADOS') as is_quintoandar_authorized,
    max(visit_information='PROPRIETARIO_PRECISA_LIBERAR') as need_owner_authorization,
    max(visit_information='CHAVE_CAIXA_QUINTOANDAR') as has_key_box
  from
    datalake_ebdb_clean.house_visit_information
  group by 1
),
house_aud as (
  select
    id_house,
    max(rev) as REV
  from
    datalake_ebdb_clean.house_aud
  where
    mod_status = 1
  group by 1
)
select
  h.id,
  h.id % 892700000 as house_short_id,
  h.rent,
  h.neighborhood,
  h.zipcode,
  h.city,
  h.complement,
  h.condo,
  h.id_condo_parent,
  h.dt_built,
  h.has_elevator,
  h.contact_email,
  h.photo_session_email,
  h.address,
  h.conservation_status,
  h.does_photographer_fill_information,
  h.iptu,
  h.lat,
  h.lng,
  h.is_furnished,
  h.finishing_level,
  h.number,
  h.bathrooms,
  h.bedrooms,
  h.suites,
  h.parking_slots,
  h.register_percent_complete,
  h.has_session_photos_email_preference,
  h.status,
  h.contact_phone_1,
  h.contact_phone_2,
  h.photos_session_phone,
  h.type,
  h.doorman_type,
  h.parking_slot_type,
  h.is_verified,
  h.id_user,
  h.promotion_code,
  h.is_quote_insurance_needed,
  h.total_value,
  h.dt_expiration,
  h.dt_first_publication,
  h.has_owner_incomplete_listing_notification,
  h.has_admin_incomplete_listing_notification,
  h.short_url,
  h.insurance_value,
  h.booking_instructions,
  h.plan_accepted,
  h.has_price_adjustment_suggestion,
  h.has_rent_sign_permission,
  h.lead_description,
  h.listing_highlight_priority,
  h.corretorAmigo as corretor_amigo, -- partners program name
  h.porteiroAmigo as porteiro_amigo, -- partners program name
  h.condo_management_information,
  h.references,
  h.is_condo_price_included,
  h.has_manual_coordinates,
  h.is_iptu_included,
  h.is_follow_up_owner_upload_photos,
  h.ts_first_verified,
  h.lead_collision_type,
  h.ts_agent_lead_payment_calculated,
  h.cover_image_name,
  h.geo_hash,
  h.listing_type,
  h.admin_info,
  h.internal_admin_info,
  NULLIF(REGEXP_EXTRACT(h.internal_admin_info, '(?<=\\[3P\\-)(.+?)(?=\\])'), '') AS partner_3p_supply,
  h.photo_booking_historic,
  h.ts_affiliate_lead_payment_calculated,
  h.has_service_bathroom,
  h.has_service_bedroom,
  h.default_neighborhood,
  h.condo_type,
  h.iptu_type,
  h.dt_availability_end,
  h.compare_price_with_average,
  h.is_warn_owner_of_visits_needed,
  h.is_listing_notifying_owner_email_sent,
  h.house_conversion_status,
  h.registration,
  h.last_confirmation_email_sent,
  h.lat_lng,
  h.ts_last_index_update,
  h.title,
  h.ts_suspension_end,
  h.id_external,
  h.is_in_negotiation,
  h.is_in_external_negotiation,
  h.ts_external_negotiation_start,
  h.cardiff_rejection_reason,
  h.ts_recapture,
  h.is_photographer_job_pending,
  h.has_requested_professional_photos,
  h.ts_last_confirmation_availability,
  h.registry,
  h.penalization_score,
  h.is_receive_default_contract_copy_needed,
  h.rank_score,
  h.ts_last_publication,
  h.is_visit_information_confirmed,
  h.id_region,
  h.dt_creation,
  h.ts_updated,
  h.id_user_registrant,
  h.total_area,
  h.land_area,
  h.predicted_price,
  h.sale_price,
  h.is_for_rent,
  h.is_for_sale,
  COALESCE(h.internal_admin_info LIKE '%[3P-%]%', FALSE) AS is_3p_supply,
  (coalesce(h.announced_by, h.id_announced_by)
    is not null) as is_imovel_v3,
  state.abbreviation as state_abbreviation,
  state.name as state_name,
  m_region.city_name as region_city_name,
  m_region.macro_name as region_macro_name,
  m_region.name as region_name,
  condo.name as condo_name,
  local.name as closest_station_name,
  o_type.name as occupant_type,
  k_type.name as key_type,
  a_a_type.name as key_location,
  r_type.name as visit_restriction,
  coalesce(r_type.name = 'Restriction', false) as has_visit_restriction,
  hrs.registration_abandoned_reason as registration_abandoned_reason,
  case
    when h.status <> 'despublicado'
      then NULL
    when h.unpublished_reason is not null
      then h.unpublished_reason
    when ure.reason = 'Imóvel indisponível'
      then 'HOUSE_NOT_AVAILABLE'
    when ure.reason = '[Auto] Proprietario confirmou indisponibilidade'
      then 'AUTO_OWNER_CONFIRMED_UNAVAILABILITY'
    when ure.reason like '[AUTO]%[RESCISAO]%'
      then 'AUTO_CONTRACT_END_DEPUBLICATION'
    when lower(ure.reason) like '%n%o concord%'
      then 'OWNER_DOESNT_AGREE'
    when ure.reason like '%Desisti%'
      then 'OWNER_GAVE_UP_RENTING'
    when ure.reason like '%MissedNegotiations%'
      then 'AUTO_OWNER_MISSED_NEGOTIATIONS_LIMIT_REACHED'
    when ure.reason like 'Imóvel alugado direto%'
      or ure.reason like '%Fechei com outro%'
      then 'OWNER_RENTING_DIRECT_WITH_TENANT'
    when ure.reason like 'Aluguei por curta%'
      then 'OWNER_RENTING_FOR_SHORT_PERIOD'
    when ure.reason = 'Imóvel alugado com imobiliária tradicional'
      or ure.reason = 'Já aluguei o imóvel'
      then 'OWNER_RENTING_WITH_OTHER_COMPANY'
    when ure.reason = 'Vou vender o imóvel'
      or ure.reason like '%vendeu o %'
      then 'OWNER_SELLING_HOUSE'
    when lower(ure.reason) like '%duplicado%'
      then 'DUPLICATED_HOUSE'
    when ure.reason like '%falta de confirmação%'
      or ure.reason like '%falta de contato%'
      or ure.reason like 'PP não responde%'
      then 'HOUSE_NOT_REACHABLE'
    when ure.reason = 'Despublicado pelo proprietário via App: Estou reformando'
      then 'APP_HOME_RENOVATION'
    when ure.reason = 'Despublicado pelo proprietário via App: Outro motivo'
      then 'APP_OTHER_REASON'
    when ure.reason = 'Despublicado pelo proprietário via App: Já aluguei'
      then 'APP_OWNER_RENTING_WITH_OTHER_COMPANY'
    when ure.reason = 'Usuário despublicou pelo app.'
      then 'APP_USER_DEPUBLISHED'
    when ure.reason like 'Usuário rejeitou%'
      then 'USER_REJECTED_TERMS'
    when ure.reason is null
      then 'UNKNOWN_NULL_VALUE'
    else 'OTHER'
  end as unpublished_reason,
  coalesce(special_condition.is_exclusive, false) as is_exclusive,
  coalesce(visit_info.has_entry_authorization, false) as has_entry_authorization,
  coalesce(visit_info.is_owner_joinning, false) as is_owner_joinning,
  coalesce(visit_info.is_quintoandar_authorized, false) as is_quintoandar_authorized,
  coalesce(visit_info.need_owner_authorization, false) as need_owner_authorization,
  coalesce(visit_info.has_key_box, false) as has_key_box,
  coalesce(io.is_enabled, false) as has_instant_offer_enabled
from
  datalake_ebdb_clean.house h
left join
  datalake_ebdb_clean.state
    on state.id = h.id_state
left join
  datalake_ebdb_clean.map_region m_region
    on h.id_region = coalesce(m_region.id,
                              m_region.id_macro,
                              m_region.id_city)
left join
  datalake_ebdb_clean.condo
    on condo.id = h.id_condo_parent
left join
  datalake_ebdb_clean.local
    on local.id = h.id_closest_station
left join datalake_ebdb_clean.access_type a_type
  on a_type.id_house = h.id
-- who lives in the house
left join datalake_ebdb_clean.occupant_type o_type
  on a_type.id_occupant = o_type.id
-- key types (e.g., password, biometric, etc.)
left join datalake_ebdb_clean.key_type k_type
  on a_type.id_type = k_type.id
-- where is the key (e.g., owner, lockbox, etc.)
left join datalake_ebdb_clean.access_authorization_type a_a_type
  on a_type.id_authorization = a_a_type.id
left join datalake_ebdb_clean.restriction_type r_type
  on a_type.id_restriction = r_type.id
-- abandoned reason
left join datalake_ebdb_clean.house_registration_status hrs
  on h.id = hrs.id_house
left join special_condition
  on special_condition.id_house = h.id
left join visit_info
  on visit_info.id_house = h.id
left join house_aud
	on house_aud.id_house = h.id
left join datalake_ebdb_clean.user_revision_entity ure
	on house_aud.rev = ure.id
left join datalake_ebdb_clean.instant_offer io
    on h.id = io.id_house