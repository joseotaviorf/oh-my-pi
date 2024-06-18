WITH inspections AS (
  SELECT
    fi.sk_inspection,
    dc.value_segment AS category,
    dc.country_code,
    frr.total_repair_request_by_owner,
    frr.total_repair_contested,
    frr.has_owner_access_review,
    frr.has_tenant_access_review,
    frr.ts_reviewed
  FROM
    dw_inspections.fact_inspection AS fi
  JOIN
    dw_inspections.dim_inspection AS di
      ON fi.sk_inspection = di.sk_inspection
  JOIN
    dw_inspections.fact_report_review AS frr
      ON fi.sk_inspection = frr.sk_inspection
  JOIN
    dw_rent.dim_contract AS dc
      ON fi.sk_contract = dc.sk_contract
  WHERE
    di.inspection_type = 'offboarding'
    AND di.status = 'reviewed'
    AND frr.ts_reviewed IS NOT NULL
),

calculation AS (
  SELECT 
      DATE_TRUNC('WEEK', ts_reviewed) AS dt_week_reference,
      category,
      country_code,
      COUNT(DISTINCT IF(has_tenant_access_review, sk_inspection, NULL)) AS inspections_tenant_review,
      COUNT(DISTINCT IF(has_owner_access_review, sk_inspection, NULL)) AS inspections_landlord_review,
      COUNT(DISTINCT IF(has_owner_access_review AND has_tenant_access_review, sk_inspection, NULL)) AS inspections_both_review,
      COUNT(DISTINCT IF(has_owner_access_review = FALSE AND has_tenant_access_review = FALSE, sk_inspection, NULL)) AS inspections_both_without_review,
      COUNT(DISTINCT IF(total_repair_contested > 0, sk_inspection, NULL)) AS tenant_contestations,
      COUNT(DISTINCT IF(total_repair_request_by_owner > 0, sk_inspection, NULL)) AS landlord_contestations,
      COUNT(DISTINCT IF(total_repair_contested + total_repair_request_by_owner > 0, sk_inspection, NULL)) AS total_contestations,
      COUNT(DISTINCT sk_inspection) AS total_inspections
  FROM
    inspections
  GROUP BY
    1, 2, 3
)

SELECT
  dt_week_reference,
  category,
  country_code,
  inspections_tenant_review,
  inspections_landlord_review,
  inspections_both_review,
  inspections_both_without_review,
  total_inspections,
  inspections_tenant_review / total_inspections AS pct_inpsections_tenant_review,
  inspections_landlord_review / total_inspections  AS pct_inspections_landlord_review,
  inspections_both_review / total_inspections AS pct_inspections_both_without_review,
  (inspections_tenant_review + inspections_landlord_review) / (2 * total_inspections) AS pct_tenant_landlord_review,
  tenant_contestations,
  landlord_contestations,
  total_contestations,
  tenant_contestations / total_inspections AS pct_tentant_contestations,
  landlord_contestations / total_inspections AS pct_landlord_contestations,
  total_contestations / total_inspections AS pct_total_contestations
FROM
  calculation

UNION ALL

SELECT
  dt_week_reference,
  'OVERALL' AS category,
  country_code,
  SUM(inspections_tenant_review) AS inspections_tenant_review,
  SUM(inspections_landlord_review) AS inspections_landlord_review,
  SUM(inspections_both_review) AS inspections_both_review,
  SUM(inspections_both_without_review) AS inspections_both_without_review,
  SUM(total_inspections) AS total_inspections,
  SUM(inspections_tenant_review) / SUM(total_inspections) AS pct_inspections_tenant_review,
  SUM(inspections_landlord_review) / SUM(total_inspections)  AS pct_inspections_landlord_review,
  SUM(inspections_both_without_review) / SUM(total_inspections) AS pct_both_without_access,
  (SUM(inspections_tenant_review) + SUM(inspections_landlord_review)) / (2 * SUM(total_inspections)) AS pct_tenant_landlord_review,
  SUM(tenant_contestations) AS tenant_contestations,
  SUM(landlord_contestations) AS landlord_contestations,
  SUM(total_contestations) AS total_contestations,
  SUM(tenant_contestations) / SUM(total_inspections) AS pct_tentant_contestations,
  SUM(landlord_contestations) / SUM(total_inspections) AS pct_landlord_contestations,
  SUM(total_contestations) / SUM(total_inspections) AS pct_total_contestations
FROM
  calculation
GROUP BY
  1, 3