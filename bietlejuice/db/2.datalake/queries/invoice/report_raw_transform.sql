with rent_delay as (
  select distinct
    "contract-id",
    item,
    purpose,
    "year-month",
    date_diff('day',
              cast((regexp_extract("tenant-due-date", '\d+/\d+/(\d+)', 1) || '-' ||
                    regexp_extract("tenant-due-date", '\d+/(\d+)/\d+', 1) || '-' ||
                    regexp_extract("tenant-due-date", '(\d+)/\d+/\d+', 1)) as timestamp),
              cast((regexp_extract("tenant-paid-date", '\d+/\d+/(\d+)', 1) || '-' ||
                    regexp_extract("tenant-paid-date", '\d+/(\d+)/\d+', 1) || '-' ||
                    regexp_extract("tenant-paid-date", '(\d+)/\d+/\d+', 1)) as timestamp)) as rent_delayed_days
  from datalake_raw.seubarriga_invoice
  where trim("from") = 'Inquilino'
    and trim(item) = 'Aluguel'
    and "tenant-due-date" != ''
    and "tenant-paid-date" != ''
    and ym = '{year_month}'
)
select distinct
  inv."contract-id",
  inv.version,
  if(lower(inv.blocked) = 'true', 'True', 'False') as blocked,
  inv."from",
  inv."to",
  inv.description,
  inv.amount,
  inv.item,
  inv."year-month",
  inv."due-date",
  inv."tenant-due-date",
  inv."tenant-paid-date",
  inv."tenant-status",
  inv."landlord-due-date",
  inv."landlord-paid-date",
  inv."landlord-status",
  cast(rd.rent_delayed_days as smallint) as delayed_days,
  inv.purpose
from datalake_raw.seubarriga_invoice inv
left join rent_delay rd
  on inv."contract-id" = rd."contract-id"
    and inv."year-month" = rd."year-month"
    and inv.item = rd.item
    and inv.purpose = rd.purpose
    and inv."tenant-due-date" != ''
    and inv."tenant-paid-date" != ''
where inv.ym = '{year_month}'
;