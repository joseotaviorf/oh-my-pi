SELECT
    id,
    imovelId AS id_house,
    listingBusinessContextId AS id_listing_business_context,
    relatedId AS id_related,
    relatedAs AS related_as,
    sourceType AS source_type,
    imovelOriginated AS house_origin,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.ImovelListingRelation
