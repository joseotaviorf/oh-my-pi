SELECT 
  region_id AS id_region,
  businessContext AS business_context,
  REV AS rev,
  REVTYPE AS rev_type
FROM 
  datalake_ebdb_raw.Regiao_businessContextsServed_AUD