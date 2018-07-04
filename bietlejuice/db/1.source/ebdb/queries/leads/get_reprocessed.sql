select
  *
from
  (
    select distinct
      case
        when SUBSTRING_INDEX(infosExtras,';',1) REGEXP '^-?[0-9]+$'
          then CAST(SUBSTRING_INDEX(infosExtras,';',1) AS UNSIGNED INTEGER)
        else NULL
      end as id,
      criadoEm as reprocessed_at
    from Lead
    where origem = 'Reprocessado'
  ) t
where id is not null