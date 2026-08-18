WITH special_condition AS (
  /* there is a known bug that creates multiple rows for some houses */
  SELECT
    hsc.id_house,
    MAX(NOT hsc.id_special_condition IS NULL) AS is_exclusive
  FROM datalake_ebdb_clean.house_special_condition AS hsc
  JOIN datalake_ebdb_clean.special_condition AS sc
    ON sc.id = hsc.id_special_condition
    AND sc.special_condition_type = 'Exclusivity'
    AND sc.special_condition_status IN ('OptedIn', 'Applied')
  GROUP BY
    1
), visit_info AS (
  SELECT
    id_house,
    MAX(visit_information = 'AUTORIZACAO_DE_ENTRADA') AS has_entry_authorization,
    MAX(visit_information = 'PROPRIETARIO_ACOMPANHA') AS is_owner_joinning,
    MAX(visit_information = 'ESTAMOS_LIBERADOS') AS is_quintoandar_authorized,
    MAX(visit_information = 'PROPRIETARIO_PRECISA_LIBERAR') AS need_owner_authorization,
    MAX(visit_information = 'CHAVE_CAIXA_QUINTOANDAR') AS has_key_box
  FROM datalake_ebdb_clean.house_visit_information
  GROUP BY
    1
), house_aud AS (
  SELECT
    id_house,
    MAX(rev) AS REV
  FROM datalake_ebdb_clean.house_aud
  WHERE
    mod_status = 1
  GROUP BY
    1
), listing_info AS (
  SELECT
    lbc.id_house,
    BOOL_OR(
      (
        lbc.ownership = 'THIRD_PARTY' AND cb.uuid_company IS NOT NULL
      )
      OR (
        COALESCE(lrm.rental_administrator = 'THIRD_PARTY', FALSE) AND cb.uuid_company IS NOT NULL
      )
    ) AS is_3p_supply,
    BOOL_OR(
      lbc.ownership = 'THIRD_PARTY'
      AND lbc.business_context = 'SALE'
      AND cb.uuid_company IS NOT NULL
    ) AS is_sale_3p_supply,
    BOOL_OR(lrm.rental_administrator = 'THIRD_PARTY' AND cb.uuid_company IS NOT NULL) AS is_rent_3p_supply,
    BOOL_OR(lsm.is_primary_market) AS is_sale_primary_market,
    BOOL_OR(lsm.has_great_sale_price_tag) AS has_sale_great_price_tag
  FROM datalake_ebdb_clean.listing_business_context AS lbc
  LEFT JOIN datalake_ebdb_clean.listing_sale_model AS lsm
    ON lbc.id = lsm.id_listing_business_context AND lbc.business_context = 'SALE'
  LEFT JOIN datalake_ebdb_clean.listing_rent_model AS lrm
    ON lbc.id = lrm.id_listing_business_context AND lbc.business_context = 'RENT'
  LEFT JOIN datalake_ebdb_clean.house_listing_relation AS hlr
    ON lbc.id_house = hlr.id_house
  LEFT JOIN core_brokers.brokers AS cb
    ON hlr.id_related = cb.uuid_company
  GROUP BY
    1
), listing_ownership_aux AS (
  SELECT
    hlr.id_house,
    MIN(hlr.id_related) AS uuid_company,
    BOOL_OR(lbc.business_context = 'SALE') AS is_sale_3p_supply,
    BOOL_OR(lbc.business_context = 'RENT') AS is_rent_3p_supply
  FROM datalake_ebdb_clean.house_listing_relation AS hlr
  INNER JOIN datalake_ebdb_clean.listing_business_context AS lbc
    ON lbc.id = hlr.id_listing_business_context
  INNER JOIN core_brokers.brokers AS cb
    ON hlr.id_related = cb.uuid_company
  WHERE
    lbc.ownership = 'THIRD_PARTY'
    AND hlr.source_type = 'COMPANY_REF'
    AND hlr.related_as = 'LISTING_OWNER'
  GROUP BY
    1
), listing_ownership AS (
  SELECT
    loa.id_house,
    loa.uuid_company,
    cb.broker_name AS partner_3p_supply,
    loa.is_sale_3p_supply,
    loa.is_rent_3p_supply
  FROM listing_ownership_aux AS loa
  LEFT JOIN core_brokers.brokers AS cb
    ON loa.uuid_company = cb.uuid_company
), smart_price AS (
  SELECT
    l.id_house,
    SOME(p.status = 'ACTIVE' AND l.business_context = 'SALE') AS has_sale_smart_price_activated,
    SOME(p.status = 'ACTIVE' AND l.business_context = 'RENT') AS has_rent_smart_price_activated
  FROM datalake_ebdb_clean.dynamic_pricing_house AS p
  INNER JOIN datalake_ebdb_clean.listing_business_context AS l
    ON l.id = p.id_listing_business_context
  GROUP BY
    1
)
SELECT
  id,
  id_country,
  id_state,
  id_region,
  id_user,
  id_user_registrant,
  id_external,
  id_condo_parent,
  uuid_company,
  house_short_id,
  rent,
  country_code,
  state_abbreviation,
  state_name,
  region_city_name,
  region_macro_name,
  region_name,
  lat,
  lng,
  neighborhood,
  zipcode,
  city,
  address,
  complement,
  condo,
  condo_name,
  building_floors,
  houses_per_floor,
  closest_station_name,
  contact_email,
  photo_session_email,
  conservation_status,
  iptu,
  finishing_level,
  number,
  floor,
  bathrooms,
  bedrooms,
  suites,
  parking_slots,
  register_percent_complete,
  status,
  contact_phone_1,
  contact_phone_2,
  photos_session_phone,
  type,
  doorman_type,
  parking_slot_type,
  promotion_code,
  total_value,
  short_url,
  insurance_value,
  booking_instructions,
  plan_accepted,
  lead_description,
  listing_highlight_priority,
  corretor_amigo,
  porteiro_amigo,
  condo_management_information,
  references,
  lead_collision_type,
  cover_image_name,
  geo_hash,
  listing_type,
  admin_info,
  internal_admin_info,
  partner_3p_supply,
  photo_booking_historic,
  default_neighborhood,
  condo_type,
  iptu_type,
  compare_price_with_average,
  house_conversion_status,
  registration,
  last_confirmation_email_sent,
  lat_lng,
  title,
  cardiff_rejection_reason,
  registry,
  penalization_score,
  rank_score,
  total_area,
  land_area,
  predicted_price,
  sale_price,
  key_location,
  occupant_type,
  key_type,
  authorization_type,
  visit_restriction,
  registration_abandoned_reason,
  unpublished_reason,
  has_elevator,
  is_furnished,
  has_session_photos_email_preference,
  does_photographer_fill_information,
  is_exclusive,
  is_quintoandar_authorized,
  is_quote_insurance_needed,
  is_verified,
  is_in_negotiation,
  is_in_external_negotiation,
  is_condo_price_included,
  has_manual_coordinates,
  is_iptu_included,
  is_follow_up_owner_upload_photos,
  is_warn_owner_of_visits_needed,
  is_listing_notifying_owner_email_sent,
  is_photographer_job_pending,
  is_receive_default_contract_copy_needed,
  is_visit_information_confirmed,
  is_for_rent,
  is_for_sale,
  is_3p_supply,
  is_sale_3p_supply,
  is_rent_3p_supply,
  is_imovel_v3,
  is_casa_mineira_migration,
  is_sale_primary_market,
  has_sale_great_price_tag,
  has_visit_restriction,
  has_requested_professional_photos,
  has_owner_incomplete_listing_notification,
  has_admin_incomplete_listing_notification,
  has_price_adjustment_suggestion,
  has_rent_sign_permission,
  has_service_bathroom,
  has_service_bedroom,
  has_entry_authorization,
  is_owner_joinning,
  need_owner_authorization,
  has_key_box,
  has_instant_offer_enabled,
  has_sale_smart_price_activated,
  has_rent_smart_price_activated,
  dt_built,
  dt_expiration,
  dt_first_publication,
  dt_availability_end,
  dt_creation,
  ts_first_verified,
  ts_suspension_end,
  ts_last_index_update,
  ts_last_confirmation_availability,
  ts_agent_lead_payment_calculated,
  ts_affiliate_lead_payment_calculated,
  ts_external_negotiation_start,
  ts_recapture,
  ts_last_publication,
  ts_updated
FROM (
  SELECT
    h.id,
    ch.id_country,
    h.id_state,
    h.id_region,
    h.id_user,
    h.id_user_registrant,
    h.id_external,
    h.id_condo_parent,
    lo.uuid_company,
    h.id % 892700000 AS house_short_id,
    h.rent,
    ch.country_code,
    state.abbreviation AS state_abbreviation,
    state.name AS state_name,
    m_region.city_name AS region_city_name,
    m_region.macro_name AS region_macro_name,
    m_region.name AS region_name,
    h.lat,
    h.lng,
    h.neighborhood,
    h.zipcode,
    h.city,
    h.address,
    h.complement,
    h.condo,
    condo.name AS condo_name,
    h.building_floors,
    h.houses_per_floor,
    local.name AS closest_station_name,
    h.contact_email,
    h.photo_session_email,
    h.conservation_status,
    h.iptu,
    h.finishing_level,
    h.number,
    h.floor,
    h.bathrooms,
    h.bedrooms,
    h.suites,
    h.parking_slots,
    h.register_percent_complete,
    h.status,
    h.contact_phone_1,
    h.contact_phone_2,
    h.photos_session_phone,
    h.type,
    h.doorman_type,
    h.parking_slot_type,
    h.promotion_code,
    h.total_value,
    h.short_url,
    h.insurance_value,
    h.booking_instructions,
    h.plan_accepted,
    h.lead_description,
    h.listing_highlight_priority,
    h.corretorAmigo AS corretor_amigo, /* partners program name */
    h.porteiroAmigo AS porteiro_amigo, /* partners program name */
    h.condo_management_information,
    h.references,
    h.lead_collision_type,
    h.cover_image_name,
    h.geo_hash,
    h.listing_type,
    h.admin_info,
    h.internal_admin_info,
    lo.partner_3p_supply,
    h.photo_booking_historic,
    h.default_neighborhood,
    h.condo_type,
    h.iptu_type,
    h.compare_price_with_average,
    h.house_conversion_status,
    h.registration,
    h.last_confirmation_email_sent,
    h.lat_lng,
    h.title,
    h.cardiff_rejection_reason,
    h.registry,
    h.penalization_score,
    h.rank_score,
    h.total_area,
    h.land_area,
    h.predicted_price,
    h.sale_price,
    entrance.key_location,
    entrance.occupant_type,
    entrance.key_type,
    entrance.authorization_type,
    entrance.restriction_type AS visit_restriction,
    hrs.registration_abandoned_reason AS registration_abandoned_reason,
    CASE
      WHEN h.status <> 'despublicado'
      THEN NULL
      WHEN NOT h.unpublished_reason IS NULL
      THEN h.unpublished_reason
      WHEN ure.reason = 'Imóvel indisponível'
      THEN 'HOUSE_NOT_AVAILABLE'
      WHEN ure.reason = '[Auto] Proprietario confirmou indisponibilidade'
      THEN 'AUTO_OWNER_CONFIRMED_UNAVAILABILITY'
      WHEN ure.reason LIKE '[AUTO]%[RESCISAO]%'
      THEN 'AUTO_CONTRACT_END_DEPUBLICATION'
      WHEN LOWER(ure.reason) LIKE '%n%o concord%'
      THEN 'OWNER_DOESNT_AGREE'
      WHEN ure.reason LIKE '%Desisti%'
      THEN 'OWNER_GAVE_UP_RENTING'
      WHEN ure.reason LIKE '%MissedNegotiations%'
      THEN 'AUTO_OWNER_MISSED_NEGOTIATIONS_LIMIT_REACHED'
      WHEN ure.reason LIKE 'Imóvel alugado direto%' OR ure.reason LIKE '%Fechei com outro%'
      THEN 'OWNER_RENTING_DIRECT_WITH_TENANT'
      WHEN ure.reason LIKE 'Aluguei por curta%'
      THEN 'OWNER_RENTING_FOR_SHORT_PERIOD'
      WHEN ure.reason = 'Imóvel alugado com imobiliária tradicional'
      OR ure.reason = 'Já aluguei o imóvel'
      THEN 'OWNER_RENTING_WITH_OTHER_COMPANY'
      WHEN ure.reason = 'Vou vender o imóvel' OR ure.reason LIKE '%vendeu o %'
      THEN 'OWNER_SELLING_HOUSE'
      WHEN LOWER(ure.reason) LIKE '%duplicado%'
      THEN 'DUPLICATED_HOUSE'
      WHEN ure.reason LIKE '%falta de confirmação%'
      OR ure.reason LIKE '%falta de contato%'
      OR ure.reason LIKE 'PP não responde%'
      THEN 'HOUSE_NOT_REACHABLE'
      WHEN ure.reason = 'Despublicado pelo proprietário via App: Estou reformando'
      THEN 'APP_HOME_RENOVATION'
      WHEN ure.reason = 'Despublicado pelo proprietário via App: Outro motivo'
      THEN 'APP_OTHER_REASON'
      WHEN ure.reason = 'Despublicado pelo proprietário via App: Já aluguei'
      THEN 'APP_OWNER_RENTING_WITH_OTHER_COMPANY'
      WHEN ure.reason = 'Usuário despublicou pelo app.'
      THEN 'APP_USER_DEPUBLISHED'
      WHEN ure.reason LIKE 'Usuário rejeitou%'
      THEN 'USER_REJECTED_TERMS'
      WHEN ure.reason IS NULL
      THEN 'UNKNOWN_NULL_VALUE'
      ELSE 'OTHER'
    END AS unpublished_reason,
    h.has_elevator,
    h.is_furnished,
    h.has_session_photos_email_preference,
    h.does_photographer_fill_information,
    COALESCE(special_condition.is_exclusive, FALSE) AS is_exclusive,
    COALESCE(visit_info.is_quintoandar_authorized, FALSE) AS is_quintoandar_authorized,
    h.is_quote_insurance_needed,
    h.is_verified,
    h.is_in_negotiation,
    h.is_in_external_negotiation,
    h.is_condo_price_included,
    h.has_manual_coordinates,
    h.is_iptu_included,
    h.is_follow_up_owner_upload_photos,
    h.is_warn_owner_of_visits_needed,
    h.is_listing_notifying_owner_email_sent,
    h.is_photographer_job_pending,
    h.is_receive_default_contract_copy_needed,
    h.is_visit_information_confirmed,
    h.is_for_rent,
    h.is_for_sale,
    COALESCE(NOT lo.id_house IS NULL OR li.is_3p_supply, FALSE) AS is_3p_supply,
    COALESCE(li.is_sale_3p_supply OR lo.is_sale_3p_supply, FALSE) AS is_sale_3p_supply,
    COALESCE(li.is_rent_3p_supply OR lo.is_rent_3p_supply, FALSE) AS is_rent_3p_supply,
    (
      NOT COALESCE(h.announced_by, h.id_announced_by) IS NULL
    ) AS is_imovel_v3,
    CASE
      WHEN (
        h.id_external LIKE '%SCM%-%' OR h.internal_admin_info LIKE '%[SCM%-%]%'
      )
      THEN TRUE
      WHEN h.id_user_registrant = 7212349
      THEN TRUE /* For Casa Mineira migration, a single user was created to import the CM listings */
      ELSE FALSE
    END AS is_casa_mineira_migration,
    COALESCE(li.is_sale_primary_market, FALSE) AS is_sale_primary_market,
    COALESCE(li.has_sale_great_price_tag, FALSE) AS has_sale_great_price_tag,
    COALESCE(entrance.restriction_type = 'Restriction', FALSE) AS has_visit_restriction,
    h.has_requested_professional_photos,
    h.has_owner_incomplete_listing_notification,
    h.has_admin_incomplete_listing_notification,
    h.has_price_adjustment_suggestion,
    h.has_rent_sign_permission,
    h.has_service_bathroom,
    h.has_service_bedroom,
    COALESCE(visit_info.has_entry_authorization, FALSE) AS has_entry_authorization,
    COALESCE(visit_info.is_owner_joinning, FALSE) AS is_owner_joinning,
    COALESCE(visit_info.need_owner_authorization, FALSE) AS need_owner_authorization,
    COALESCE(visit_info.has_key_box, FALSE) AS has_key_box,
    COALESCE(io.is_enabled, FALSE) AS has_instant_offer_enabled,
    COALESCE(has_sale_smart_price_activated, FALSE) AS has_sale_smart_price_activated,
    COALESCE(has_rent_smart_price_activated, FALSE) AS has_rent_smart_price_activated,
    h.dt_built,
    h.dt_expiration,
    COALESCE(
      IF(lbc.business_context = 'RENT', lbc.ts_first_publication, NULL),
      h.dt_first_publication
    ) AS dt_first_publication,
    h.dt_availability_end,
    h.dt_creation,
    h.ts_first_verified,
    h.ts_suspension_end,
    h.ts_last_index_update,
    h.ts_last_confirmation_availability,
    h.ts_agent_lead_payment_calculated,
    h.ts_affiliate_lead_payment_calculated,
    h.ts_external_negotiation_start,
    h.ts_recapture,
    h.ts_last_publication,
    h.ts_updated,
    ROW_NUMBER() OVER (PARTITION BY h.id ORDER BY IF(lbc.business_context = 'RENT', 1, 2)) AS _w,
    lbc.business_context
  FROM datalake_ebdb_clean.house AS h
  LEFT JOIN datalake_ebdb_clean.listing_business_context AS lbc
    ON lbc.id_house = h.id
  LEFT JOIN datalake_ebdb_clean.state
    ON state.id = h.id_state
  LEFT JOIN datalake_ebdb_country.house AS ch
    ON ch.id_house = h.id
  LEFT JOIN datalake_ebdb_clean.map_region AS m_region
    ON h.id_region = COALESCE(m_region.id, m_region.id_macro, m_region.id_city)
  LEFT JOIN datalake_ebdb_clean.condo
    ON condo.id = h.id_condo_parent
  LEFT JOIN datalake_ebdb_clean.local
    ON local.id = h.id_closest_station
  LEFT JOIN datalake_ebdb_listing.house_entrance AS entrance
    ON entrance.id_house = h.id
  /* abandoned reason */
  LEFT JOIN datalake_ebdb_clean.house_registration_status AS hrs
    ON h.id = hrs.id_house
  LEFT JOIN special_condition
    ON special_condition.id_house = h.id
  LEFT JOIN visit_info
    ON visit_info.id_house = h.id
  LEFT JOIN house_aud
    ON house_aud.id_house = h.id
  LEFT JOIN datalake_ebdb_clean.user_revision_entity AS ure
    ON house_aud.rev = ure.id
  LEFT JOIN datalake_ebdb_clean.instant_offer AS io
    ON h.id = io.id_house
  LEFT JOIN listing_info AS li
    ON h.id = li.id_house
  LEFT JOIN listing_ownership AS lo
    ON lo.id_house = h.id
  LEFT JOIN smart_price AS sp
    ON sp.id_house = h.id
) AS _t
WHERE
  _w = 1
