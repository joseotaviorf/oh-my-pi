SELECT
    id,
    shopWindow_id AS id_shop_window,
    listingBusinessContext_id AS id_listing_business_context,
    isActive AS is_active,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_test_raw.shopwindow_listingbusinesscontext
