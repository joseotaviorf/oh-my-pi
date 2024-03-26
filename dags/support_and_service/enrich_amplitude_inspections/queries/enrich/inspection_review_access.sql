WITH inspections AS (
  SELECT DISTINCT
    id_inspection,
    id_client_side,
    id_contract,
    inspection_type,
    ts_created,
    ts_updated
  FROM
    datalake_inspections_clean.inspection_aud AS ia
  QUALIFY
    ia.ts_updated = MAX(ia.ts_updated) OVER(PARTITION BY ia.id_inspection)
)
SELECT
    ia.id_inspection,
    ia.id_client_side,
    ia.id_contract,
    ia.inspection_type,
    COALESCE(SUM(CAST(insp.user_type = 'Proprietario' AS SMALLINT)), 0) AS total_owner_access_review,
    COALESCE(MAX(insp.user_type = 'Proprietario'), FALSE) AS has_owner_access_review,
    COALESCE(SUM(CAST(insp.user_type = 'Inquilino' AS SMALLINT)), 0) AS total_tenant_access_review,
    COALESCE(MAX(insp.user_type = 'Inquilino'), FALSE) AS has_tenant_access_review,
    MIN(
        CASE 
         WHEN insp.user_type = 'Proprietario' THEN insp.ts_event
        END
    ) AS ts_first_owner_access_review,
    MAX(
        CASE 
            WHEN insp.user_type = 'Proprietario' THEN insp.ts_event
        END
    ) AS ts_last_owner_access_review,    
    MIN(
        CASE 
          WHEN insp.user_type = 'Inquilino' THEN insp.ts_event
        END
    ) AS ts_first_tenant_access_review,
    MAX(
        CASE 
            WHEN insp.user_type = 'Inquilino' THEN insp.ts_event
        END
    ) AS ts_last_tenant_access_review,
    ia.ts_created AS ts_inspection_created,
    ia.ts_updated AS ts_inspection_updated
FROM
    inspections AS ia
LEFT JOIN
    datalake_amplitude_inspections.inspection_review_page_viewed_events AS insp
        ON insp.id_client_side = ia.id_client_side
GROUP BY 1, 2, 3, 4, 13, 14