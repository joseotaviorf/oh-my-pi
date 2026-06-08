SELECT
    id AS id_house_listing_relation,
    imovelId AS id_house,
    listingBusinessContextId AS id_listing_business_context,
    relatedId AS id_related,
    REV AS rev,
    REVTYPE AS rev_type,
    sourceType AS source_type,
    relatedAs AS related_as,
    imovelOriginated AS house_origin,
    imovelId_MOD AS mod_id_house,
    listingBusinessContextId_MOD AS mod_id_listing_business_context,
    sourceType_MOD AS mod_source_type,
    relatedId_MOD AS mod_id_related,
    relatedAs_MOD AS mod_related_as,
    imovelOriginated_MOD AS mod_house_origin,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.ImovelListingRelation_AUD
