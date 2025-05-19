WITH merged_companies_aux AS (
  SELECT
    ids_merged_companies
  FROM
    datalake_hubspot.company_history
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_company ORDER BY ts_updated DESC) = 1
),
merged_companies AS (
  SELECT
    EXPLODE(ids_merged_companies) AS id_merged_company
  FROM
    merged_companies_aux
)
SELECT
  ch.id_company,
  ch.id_hubspot_owner,
  ch.cnpj,
  ch.company_cluster,
  ch.name AS company_name,
  ch.cluster_performance AS company_cluster_performance,
  ch.crm,
  ch.extracted_3p_tag,
  ch.member_category,
  ch.sale_lead_status,
  ch.is_flagged_as_leadgen,
  ch.ts_created,
  ch.ts_updated,
  ch.year,
  ch.month,
  ch.day
FROM
  datalake_hubspot.company_history AS ch
LEFT JOIN
  merged_companies AS mc
    ON ch.id_company = mc.id_merged_company
WHERE
    COALESCE(
      ARRAY_CONTAINS(sale_lead_status_history.value, 'Membro')
        OR ARRAY_CONTAINS(sale_lead_status_history.value, 'Parceiro'),
      FALSE
    )
    AND NOT(ch.is_archived)
    AND mc.id_merged_company IS NULL
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY ch.id_company ORDER BY ch.ts_updated DESC) = 1
    AND ROW_NUMBER() OVER(PARTITION BY ch.cnpj ORDER BY ch.ts_updated DESC) = 1