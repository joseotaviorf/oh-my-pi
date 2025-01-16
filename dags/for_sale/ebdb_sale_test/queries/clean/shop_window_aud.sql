SELECT
    id AS id_shop_window,
    shopWindowCreatorId AS id_shop_window_creator,
    agentsProspect_id AS id_agents_prospect,
    externalId AS id_external,
    name AS shop_window_name,
    shopWindowCreatorUserType AS shop_window_creator_user_type,
    shortUrl AS short_url,
    coverImageUri AS cover_image_uri,
    rev,
    revtype AS rev_type,
    isActive AS is_active,
    shopWindowCreatorId_MOD AS mod_id_shop_window_creator,
    agentsProspect_id_MOD AS mod_id_agents_prospect,
    externalId_MOD AS mod_id_external,
    name_MOD AS mod_shop_window_name,
    shopWindowCreatorUserType_MOD AS mod_shop_window_creator_user_type,
    shortUrl_MOD AS mod_short_url,
    coverImageUri_MOD AS mod_cover_image_uri,
    isActive_MOD AS mod_is_active
FROM
    datalake_ebdb_test_raw.shopwindow_aud
