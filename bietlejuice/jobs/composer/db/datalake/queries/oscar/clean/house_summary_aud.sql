select 
  id as id_house,
  rev,
  revtype as rev_type,
  rent_value as rent,
  type,
  neighborhood,
  address,
  number,
  complement
from datalake_oscar_raw.house_summary_aud