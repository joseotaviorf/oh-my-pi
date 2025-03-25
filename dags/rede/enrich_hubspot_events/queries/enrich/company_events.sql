WITH events AS (
  SELECT
    cu.id_cluster_update AS id_event,
    cu.id_hubspot,
    cu.company_cluster AS event_update,
    'Cluster Update' AS event_type,
    'Hubspot Cluster Information' AS event_source,
    cu.is_current_cohort,
    cu.ts_start,
    cu.ts_end
  FROM
    datalake_hubspot.cluster_updates AS cu

  UNION ALL

  SELECT
    mu.id_membership_update AS id_event,
    mu.id_hubspot,
    mu.hubspot_status AS event_update,
    'Membership Update' AS event_type,
    'Hubspot Lead Status Information' AS event_source,
    mu.is_current_cohort,
    mu.ts_start,
    mu.ts_end
  FROM
    datalake_hubspot.membership_updates AS mu

  UNION ALL

  SELECT
    ou.id_owner_update AS id_event,
    ou.id_hubspot,
    ou.uuid_person AS event_update,
    'Owner Update' AS event_type,
    'Hubspot Owner UUID Person information' AS event_source,
    ou.is_current_cohort,
    ou.ts_start,
    ou.ts_end
  FROM
    datalake_hubspot.owner_updates AS ou
)
SELECT
  CONCAT(e.id_event, CRC32(CONCAT(cs.sk_company, e.event_type, e.event_source))) AS id_event,
  e.id_hubspot,
  cs.sk_company,
  e.event_update,
  e.event_type,
  e.event_source,
  e.is_current_cohort,
  e.ts_start,
  e.ts_end
FROM
  events AS e
LEFT JOIN
  datalake_company.company_sks AS cs
    ON e.id_hubspot = cs.id_hubspot