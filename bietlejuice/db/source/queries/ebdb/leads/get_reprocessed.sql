select distinct
  CAST(SUBSTRING_INDEX(infosExtras,';',1) AS UNSIGNED INTEGER) as id,
  criadoEm as reprocessed_at
from Lead
where origem = 'Reprocessado'
  and SUBSTRING_INDEX(infosExtras,';',1) REGEXP '^-?[0-9]+$'