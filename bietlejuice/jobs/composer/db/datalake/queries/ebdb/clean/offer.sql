SELECT
  id,
  firestoreId as id_firestore,
  godfatherId as id_godfather,
  client_id as id_client,
  house_id as id_house,
  rentFlow_id as id_rent_flow,
  originalCondo as original_condo,
  originalHomeInsurance as original_home_insurance,
  originalIptu as original_iptu,
  originalRent as original_rent,
  rent,
  "status",
  turn,
  rejectionReason as rejection_reason,
  criadoEm as ts_created,
  atualizadoEm as ts_updated
FROM datalake_ebdb_raw.Offer
