WITH rep_leads AS (
    WITH base_leads AS (
      SELECT
        lead.id AS id_lead,
        lead.type AS lead_type,
        lead.source AS lead_origin,
        lead.utm_source,
        lead.utm_medium,
        COALESCE(
            LOWER(TRIM(lead.utm_campaign)) RLIKE '(institucional)|(branded)'
                AND LOWER(TRIM(lead.utm_campaign)) NOT RLIKE '(non-branded)',
            FALSE
        ) AS branded_lead,
        (
            lead.real_estate_agency_code IS NOT NULL
            OR lead.is_b2b
        ) AS is_b2b,
        CASE
            WHEN lead.source = 'Reprocessado'
                THEN rl.id_origin_lead
            ELSE NULL
        END AS old_id_lead
      FROM datalake_lead.lead lead
      LEFT JOIN datalake_lead.reprocessed_lead rl
            ON rl.id = lead.id
    )
    SELECT
      bl.id_lead,
      COALESCE(old_bl.lead_type, bl.lead_type) AS lead_type,
      COALESCE(old_bl.lead_origin, bl.lead_origin) AS lead_origin,
      COALESCE(old_bl.utm_source, bl.utm_source) AS utm_source,
      COALESCE(old_bl.utm_medium, bl.utm_medium) AS utm_medium,
      COALESCE(old_bl.branded_lead, bl.branded_lead) AS is_lead_branded,
      COALESCE(bl.lead_origin = 'Reprocessado', FALSE) AS is_reprocessed,
      COALESCE(old_bl.is_b2b, bl.is_b2b) AS is_b2b
    FROM base_leads bl
    LEFT JOIN base_leads old_bl
      ON old_bl.id_lead = bl.old_id_lead
)
SELECT
    lfrl.id,
    rl.lead_type,
    rl.lead_origin,
    rl.utm_source,
    rl.utm_medium,
    rl.is_lead_branded,
    rl.is_reprocessed,
    rl.is_b2b
FROM datalake_listing_flow.sales_listing_flows_with_reprocessed_leads AS lfrl
JOIN rep_leads AS rl
    ON rl.id_lead = lfrl.id_lead