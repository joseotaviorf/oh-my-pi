with rent_delay as (
  select distinct
    id_contract,
    item,
    purpose,
    ref_item_ym,
    date_diff('day',
               cast((if(cast(regexp_extract(tenant_due_date, '\d+/\d+/(\d+)', 1) as smallint) < 2000,
				                cast((cast(regexp_extract(tenant_due_date, '\d+/\d+/(\d+)', 1) as smallint) + 2000) as varchar),
				                cast(cast(regexp_extract(tenant_due_date, '\d+/\d+/(\d+)', 1) as smallint) as varchar)
				             ) || '-' ||
                     regexp_extract(tenant_due_date, '\d+/(\d+)/\d+', 1) || '-' ||
                     regexp_extract(tenant_due_date, '(\d+)/\d+/\d+', 1)
                    ) as timestamp),
               cast((if(cast(regexp_extract(tenant_paid_date, '\d+/\d+/(\d+)', 1) as smallint) < 2000,
				                cast((cast(regexp_extract(tenant_paid_date, '\d+/\d+/(\d+)', 1) as smallint) + 2000) as varchar),
				                cast(cast(regexp_extract(tenant_paid_date, '\d+/\d+/(\d+)', 1) as smallint) as varchar)
				             ) || '-' ||
                     regexp_extract(tenant_paid_date, '\d+/(\d+)/\d+', 1) || '-' ||
                     regexp_extract(tenant_paid_date, '(\d+)/\d+/\d+', 1)
                    ) as timestamp)
              ) as rent_delayed_days
  from datalake_raw.seu_barriga_invoice_report
  where trim(item_from) = 'Inquilino'
    and trim(item) = 'Aluguel'
    and coalesce(tenant_due_date, '') != ''
    and coalesce(tenant_paid_date, '') != ''
    and ym = '{year_month}'
)
select distinct
  inv.id_contract,
  inv.version,
  if(lower(inv.blocked) = 'true', 'True', 'False') as blocked,
  inv.item_from,
  inv.item_to,
  inv.description,
  replace(inv.amount, ',', '.') as amount,
  inv.item,
  inv.ref_item_ym,
  date(date_parse(inv.due_date, '%d/%m/%Y')) as dt_due,
  date(date_parse(inv.tenant_due_date, '%d/%m/%Y')) as dt_tenant_due,
  date(date_parse(inv.tenant_paid_date, '%d/%m/%Y')) as dt_tenant_paid,
  inv.tenant_status,
  date(date_parse(inv.landlord_due_date, '%d/%m/%Y')) as dt_landlord_due,
  date(date_parse(inv.landlord_paid_date, '%d/%m/%Y')) as dt_landlord_paid,
  inv.landlord_status,
  cast(rd.rent_delayed_days as integer) as days_delayed,
  inv.purpose,
  date(date_parse(inv.tenant_invoice_created_at, '%d/%m/%Y')) as dt_tenant_invoice_created,
  date(date_parse(inv.landlord_invoice_created_at, '%d/%m/%Y')) as dt_landlord_invoice_created
from datalake_raw.seu_barriga_invoice_report inv
left join rent_delay rd
  on inv.id_contract = rd.id_contract
    and inv.ref_item_ym = rd.ref_item_ym
    and inv.item = rd.item
    and inv.purpose = rd.purpose
    and coalesce(inv.tenant_due_date, '') != ''
    and coalesce(inv.tenant_paid_date, '') != ''
where inv.ym = '{year_month}'
;