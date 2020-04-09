with filtered_custom_fields AS (
  SELECT
    zcf.id_ticket,
    field,
    replace(regexp_extract(field, '^.*='), '=', '') as id_field,
    regexp_extract(field, '^[^=]+=\[?"(.*)?"\]?$', 1) as contact_type_tag,
    cast(max(ts_updated) as timestamp with time zone) as ts_updated
  FROM datalake_clean.zendesk_custom_fields zcf
  CROSS JOIN UNNEST(
    split(zcf.custom_fields, ',')
  ) AS f(field)
  WHERE
    dt_extracted = '{extraction_date}' 
    and field LIKE '%Motivo de contato%'
  GROUP BY 1,2,3,4
),
check_prefix as (
  SELECT
    id_ticket,
    contact_type_tag,
    case
        when
          upper(split_part(contact_type_tag,'_',1)) in ('IQ', 'PP', 'CR', 'FT', 'VT', 'CD', 'AF', 'PO', 'PS')
          then 1
          else 0
    end as has_valid_prefix
  FROM filtered_custom_fields
)
SELECT
  distinct fcf.id_ticket as sk_ticket,  
  coalesce(cast(date_format(fcf.ts_updated, '%Y%m%d') as integer), -1) as sk_updated,
  fcf.contact_type_tag,
  case when cp.has_valid_prefix = 1 then upper(split_part(fcf.contact_type_tag,'_', 1)) else 'OTHER' end as client_taxonomy,
  case
    when (cp.has_valid_prefix = 1 and length(split_part(fcf.contact_type_tag,'_', 2)) <= 2) then upper(split_part(fcf.contact_type_tag,'_', 2)) 
    else 'OTHER' 
  end as category_taxonomy,
  fcf.ts_updated,
  now() as ts_load
FROM filtered_custom_fields fcf
JOIN check_prefix cp on fcf.contact_type_tag = cp.contact_type_tag AND fcf.id_ticket = cp.id_ticket
WHERE id_field IS NOT NULL