SELECT
    id,
    regionConfig_id AS id_region_config,
    businessContext AS business_context,
    maxPrice AS max_price,
    minPrice AS min_price,
    houseReferralEnabled AS is_house_referral_enabled,
    houseRegistrationEnabled AS is_house_registration_enabled,
    searchEnabled AS is_search_enabled,
    visitsEnabled AS is_visit_enabled,
    addressNumberRequired AS is_address_number_required,
    talkToAgentEnabled AS is_talk_to_agent_enabled,
    isPfaEnabled AS is_pfa_enabled,
    isKeysWithAgentEnabled AS is_keys_with_agent_enabled,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM 
    datalake_ebdb_raw.regionparameters