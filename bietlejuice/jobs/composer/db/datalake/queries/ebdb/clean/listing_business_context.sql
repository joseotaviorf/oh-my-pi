select
  id,
  imovelId as id_house,
  businessContext as business_context,
  status,
  statusReason as status_reason,
  closingStatus as status_closing,
  criadoEm as ts_created,
  atualizadoEm as ts_updated,
  firstPublicationDate as ts_first_publication,
  lastPublicationDate as ts_last_publication,
  shortUrl as short_url,
  calculatorPrice as calculator_price,
  selectedAction as selected_action
from datalake_ebdb_raw.listingbusinesscontext
