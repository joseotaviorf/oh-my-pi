SELECT
  id,
  imovelId AS id_house,
  businessContext AS business_context,
  status,
  statusReason AS status_reason,
  closingStatus AS status_closing,
  suspensionReason AS suspension_reason,
  criadoEm AS ts_created,
  atualizadoEm AS ts_updated,
  firstPublicationDate AS ts_first_publication,
  lastPublicationDate AS ts_last_publication,
  shortUrl AS short_url,
  calculatorPrice AS calculator_price,
  selectedAction AS selected_action,
  ownership
FROM
  datalake_ebdb_raw.listingbusinesscontext
