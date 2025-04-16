WITH current_members AS (
  SELECT
    c.cnpj
  FROM
    datalake_hubspot.company AS c
  WHERE
    c.sale_lead_status = 'Membro'
)
SELECT
  cm.id_company,
  cm.id_hubspot_owner,
  cm.cnpj,
  cm.company_cluster,
  cm.name AS company_name,
  cm.cluster_performance AS company_cluster_performance,
  cm.crm,
  cm.extracted_3p_tag,
  cm.member_category,
  cm.sale_lead_status,
  cm.is_flagged_as_leadgen,
  cm.ts_created,
  cm.ts_updated,
  cm.year,
  cm.month,
  cm.day
FROM
  datalake_hubspot.company AS cm
WHERE
  cm.sale_lead_status = 'Membro'
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY cm.cnpj ORDER BY cm.ts_updated DESC) = 1

UNION ALL

SELECT
  co.id_company,
  co.id_hubspot_owner,
  co.cnpj,
  co.company_cluster,
  co.name AS company_name,
  co.cluster_performance AS company_cluster_performance,
  co.crm,
  co.extracted_3p_tag,
  co.member_category,
  co.sale_lead_status,
  co.is_flagged_as_leadgen,
  co.ts_created,
  co.ts_updated,
  co.year,
  co.month,
  co.day
FROM
  datalake_hubspot.company AS co
LEFT JOIN
  current_members AS cm
    ON co.cnpj = cm.cnpj
WHERE
  (co.has_been_rent_member OR co.has_been_sale_member)
    AND co.sale_lead_status != 'Membro'
    AND cm.cnpj IS NULL
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY co.cnpj ORDER BY co.ts_updated DESC) = 1