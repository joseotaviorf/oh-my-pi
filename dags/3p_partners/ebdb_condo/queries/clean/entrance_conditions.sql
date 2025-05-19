SELECT
  id,
  imovel_id AS id_house,
  keyLocation AS key_location,
  keyLocationDetails AS key_location_details,
  chavesNaPortaria AS is_key_in_concierge,
  disponivelVistoria AS is_visit_available,
  proprietarioAcompanhaVistoria AS is_landlord_monitor_inspection,
  chavesComContrato AS is_key_with_contract,
  criadoEm AS ts_created,
  atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.CondicoesEntrada