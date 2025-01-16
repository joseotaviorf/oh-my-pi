SELECT
  id,
  houseId AS id_house,
  type,
  lastStep AS last_step,
  controlCounter AS control_counter,
  communicationSentAt AS ts_communication_sent,
  salePriceLastChangedAt AS ts_price_last_changed,
  createdAt AS ts_created,
  updatedAt AS ts_updated
FROM
  datalake_ebdb_test_raw.SaleOperationManagement
