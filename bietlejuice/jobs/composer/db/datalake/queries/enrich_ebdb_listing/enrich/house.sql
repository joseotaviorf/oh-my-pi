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
),
supply_context AS (
  SELECT
    id_house,
    SOME(ownership = 'THIRD_PARTY') AS is_3p_supply
  FROM
    datalake_ebdb_clean.listing_business_context
  GROUP BY
    1
),
-- While we don't have 3P agencies included in datalake_company_clean.company, we need to find their name via HubSpot
-- This is a temporary measure, and should be changed in 22Q3
-- Also, the reason we are not using the enriched HubSpot tables is because they run later than this query, so we can't simplify it
partner_agencies AS (
  SELECT
    NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(properties, '$.tag_imobiliarias'), '(?<=\\[3[P|p]\\-)(.+?)(?=\\])'), '') AS partner_3p_supply,
    REGEXP_REPLACE(GET_JSON_OBJECT(properties, '$.cnpj'), '[^0-9]', '') AS cnpj,
    ROW_NUMBER() OVER (
      PARTITION BY
        REGEXP_REPLACE(GET_JSON_OBJECT(properties, '$.cnpj'), '[^0-9]', '')
      ORDER BY
        ts_updated
      DESC
  ) AS rw
  FROM
    datalake_hubspot_clean.company
),
partner_agencies_deduplicated AS (
    SELECT
      partner_3p_supply,
      cnpj
    FROM
        partner_agencies
    WHERE
      rw = 1
      AND partner_3p_supply IS NOT NULL
)
SELECT
  h.id,
  COALESCE(ct.id, region.id_country) AS id_country,
  h.id_state,
  h.id_region,
  h.id_user,
  h.id_user_registrant,
  h.id_external,
  h.id_condo_parent,
  h.id % 892700000 AS house_short_id,
  h.rent,
  COALESCE(ct.code, region.country_code) AS country_code,
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
  local.name AS closest_station_name,
  h.contact_email,
  h.photo_session_email,
  h.conservation_status,
  h.iptu,
  h.finishing_level,
  h.number,
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
  h.corretorAmigo AS corretor_amigo, -- partners program name
  h.porteiroAmigo AS porteiro_amigo, -- partners program name
  h.condo_management_information,
  h.references,
  h.lead_collision_type,
  h.cover_image_name,
  h.geo_hash,
  h.listing_type,
  h.admin_info,
  h.internal_admin_info,
  COALESCE(
    pad.partner_3p_supply, -- should be replaced by company
    NULLIF(REGEXP_EXTRACT(h.internal_admin_info, '(?<=\\[3[P|p]\\-)(.+?)(?=\\])'), '') -- should be replaced by supply processor
  ) AS partner_3p_supply,
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
  o_type.name AS occupant_type,
  k_type.name AS key_type,
  a_a_type.name AS key_location,
  r_type.name AS visit_restriction,
  hrs.registration_abandoned_reason AS registration_abandoned_reason,
  CASE
    WHEN h.status <> 'despublicado' THEN NULL
    WHEN h.unpublished_reason IS NOT NULL THEN h.unpublished_reason
    WHEN ure.reason = 'Imóvel indisponível' THEN 'HOUSE_NOT_AVAILABLE'
    WHEN ure.reason = '[Auto] Proprietario confirmou indisponibilidade' THEN 'AUTO_OWNER_CONFIRMED_UNAVAILABILITY'
    WHEN ure.reason LIKE '[AUTO]%[RESCISAO]%' THEN 'AUTO_CONTRACT_END_DEPUBLICATION'
    WHEN LOWER(ure.reason) LIKE '%n%o concord%' THEN 'OWNER_DOESNT_AGREE'
    WHEN ure.reason LIKE '%Desisti%' THEN 'OWNER_GAVE_UP_RENTING'
    WHEN ure.reason LIKE '%MissedNegotiations%' THEN 'AUTO_OWNER_MISSED_NEGOTIATIONS_LIMIT_REACHED'
    WHEN ure.reason LIKE 'Imóvel alugado direto%'
      OR ure.reason LIKE '%Fechei com outro%' THEN 'OWNER_RENTING_DIRECT_WITH_TENANT'
    WHEN ure.reason LIKE 'Aluguei por curta%' THEN 'OWNER_RENTING_FOR_SHORT_PERIOD'
    WHEN ure.reason = 'Imóvel alugado com imobiliária tradicional'
      OR ure.reason = 'Já aluguei o imóvel' THEN 'OWNER_RENTING_WITH_OTHER_COMPANY'
    WHEN ure.reason = 'Vou vender o imóvel'
      OR ure.reason LIKE '%vendeu o %' THEN 'OWNER_SELLING_HOUSE'
    WHEN LOWER(ure.reason) LIKE '%duplicado%' THEN 'DUPLICATED_HOUSE'
    WHEN ure.reason LIKE '%falta de confirmação%'
      OR ure.reason LIKE '%falta de contato%'
      OR ure.reason LIKE 'PP não responde%' THEN 'HOUSE_NOT_REACHABLE'
    WHEN ure.reason = 'Despublicado pelo proprietário via App: Estou reformando' THEN 'APP_HOME_RENOVATION'
    WHEN ure.reason = 'Despublicado pelo proprietário via App: Outro motivo' THEN 'APP_OTHER_REASON'
    WHEN ure.reason = 'Despublicado pelo proprietário via App: Já aluguei' THEN 'APP_OWNER_RENTING_WITH_OTHER_COMPANY'
    WHEN ure.reason = 'Usuário despublicou pelo app.' THEN 'APP_USER_DEPUBLISHED'
    WHEN ure.reason LIKE 'Usuário rejeitou%' THEN 'USER_REJECTED_TERMS'
    WHEN ure.reason IS NULL THEN 'UNKNOWN_NULL_VALUE'
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
  CASE
    WHEN sc.is_3p_supply THEN TRUE -- After supply processor is in production, the ELSE part should be discarded.
    ELSE COALESCE(UPPER(h.internal_admin_info) LIKE '%[3P-%]%', FALSE)
  END AS is_3p_supply,
  (COALESCE(h.announced_by, h.id_announced_by) IS NOT NULL) AS is_imovel_v3,
  COALESCE(r_type.name = 'Restriction', FALSE) AS has_visit_restriction,
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
  h.dt_built,
  h.dt_expiration,
  h.dt_first_publication,
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
  h.ts_updated
FROM
  datalake_ebdb_clean.house AS h
LEFT JOIN
  datalake_ebdb_clean.state
    ON state.id = h.id_state
LEFT JOIN
  datalake_ebdb_clean.country AS ct
    ON ct.id = state.id_country
LEFT JOIN
  datalake_ebdb_clean.map_region AS m_region
    ON h.id_region = COALESCE(m_region.id,
                              m_region.id_macro,
                              m_region.id_city)
-- As we have several ids on House that has id_state null and would end up with no country info,
-- this join between map_region and region attributes a country using the respective id_region
LEFT JOIN
  datalake_region.region
    ON region.id = m_region.id
LEFT JOIN
  datalake_ebdb_clean.condo
    ON condo.id = h.id_condo_parent
LEFT JOIN
  datalake_ebdb_clean.local
    ON local.id = h.id_closest_station
LEFT JOIN
  datalake_ebdb_clean.access_type AS a_type
    ON a_type.id_house = h.id
-- who lives in the house
LEFT JOIN
  datalake_ebdb_clean.occupant_type AS o_type
    ON a_type.id_occupant = o_type.id
-- key types (e.g., password, biometric, etc.)
LEFT JOIN
  datalake_ebdb_clean.key_type AS k_type
    ON a_type.id_type = k_type.id
-- where is the key (e.g., owner, lockbox, etc.)
LEFT JOIN
  datalake_ebdb_clean.access_authorization_type AS a_a_type
    ON a_type.id_authorization = a_a_type.id
LEFT JOIN
  datalake_ebdb_clean.restriction_type AS r_type
    ON a_type.id_restriction = r_type.id
-- abandoned reason
LEFT JOIN
  datalake_ebdb_clean.house_registration_status AS hrs
    ON h.id = hrs.id_house
LEFT JOIN
  special_condition
    ON special_condition.id_house = h.id
LEFT JOIN
  visit_info
    ON visit_info.id_house = h.id
LEFT JOIN
  house_aud
	ON house_aud.id_house = h.id
LEFT JOIN
  datalake_ebdb_clean.user_revision_entity AS ure
	ON house_aud.rev = ure.id
LEFT JOIN
  datalake_ebdb_clean.instant_offer AS io
    ON h.id = io.id_house
LEFT JOIN
  supply_context AS sc
    ON h.id = sc.id_house
LEFT JOIN
  partner_agencies_deduplicated AS pad
    ON pad.cnpj = NULLIF(REGEXP_EXTRACT(h.internal_admin_info, '(?<=\\[3[P|p]\\-)(.+?)(?=\\])'), '')