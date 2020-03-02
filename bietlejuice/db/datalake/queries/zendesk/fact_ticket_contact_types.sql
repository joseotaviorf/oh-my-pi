with filtered_custom_fields AS (
  SELECT
    distinct zcf.id_ticket,
    field,
    replace(regexp_extract(field, '^.*='), '=', '') as id_field,
    replace(replace(replace(replace(regexp_extract(field, '\=(.*)'), '=', ''), '[', ''), ']', ''), '"', '') as contact_type_tag
  FROM zendesk_custom_fields zcf
  CROSS JOIN UNNEST(
      split(zcf.custom_fields, ',')
  ) AS f(field)
  WHERE field LIKE '%Motivo de contato%'
),
check_prefix as (
  SELECT
    id_ticket,
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
  fcf.contact_type_tag,
  case when cp.has_valid_prefix = 1 then upper(split_part(fcf.contact_type_tag,'_', 1)) else 'OTHER' end as client_taxonomy,
  case when cp.has_valid_prefix = 1 then upper(split_part(fcf.contact_type_tag,'_', 2)) else 'OTHER' end as category_taxonomy
FROM filtered_custom_fields fcf
JOIN check_prefix cp on fcf.id_ticket = cp.id_ticket
WHERE id_field IS NOT NULL