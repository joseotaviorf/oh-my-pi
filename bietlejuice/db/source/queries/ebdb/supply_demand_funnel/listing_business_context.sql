SELECT
  id,
  imovelId as id_house,
  businessContext as business_context,
  status as status,
  statusReason as status_reason,
  criadoEm as ts_created,
  atualizadoEm as ts_updated,
  firstPublicationDate as ts_first_listing,
  lastPublicationDate as  ts_last_listing
FROM
  ListingBusinessContext