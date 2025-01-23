SELECT
    id,
    shopWindow_id AS id_shop_window,
    listingBusinessContext_id AS id_listing_business_context,
    rev,
    revtype AS rev_type,
    isActive AS is_active,
    shopWindow_id_MOD AS mod_id_shop_window,
    listingBusinessContext_id_MOD AS mod_id_listing_business_context,
    isActive_MOD AS mod_is_active
FROM
    datalake_ebdb_raw.shopwindow_listingbusinesscontext_aud
