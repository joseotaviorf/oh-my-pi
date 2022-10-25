SELECT 
  id,
  rev,
  revtype,
  revend,
  salescompany AS sales_company,
  salescompany_mod AS mod_sales_company
FROM 
  datalake_wololo_raw.prospectdimension_aud