SELECT
    id AS id_shop_window,
    shopWindowCreatorId AS id_shop_window_creator,
    agentsProspect_id AS id_agents_prospect,
    externalId AS id_external,
    name AS shop_window_name,
    shopWindowCreatorUserType AS shop_window_creator_user_type,
    shortUrl AS short_url,
    coverImageUri AS cover_image_uri,
    isActive AS is_active,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_test_raw.shopwindow
