WITH enriched_data AS (
    SELECT 
        hda.id AS id_draft,
        sp.id_external AS id_house,
        COALESCE(h.id_region, l.id_region) AS id_region,
        COALESCE(h.city, l.city) AS city,
        r.id_main AS id_user_registrant,
        EXPLODE(
            ARRAY(
                IF(hda.is_for_rent, 'RENT', NULL),
                IF(hda.is_for_sale, 'SALE', NULL)
            )
        ) AS business_context,
        hda.status,
        hda.type,
        hda.ops_team,
        hda.ops_company,
        hda.ops_contact_type,
        hda.ops_contact_channel,
        hda.ts_created,
        hda.ts_updated
    FROM datalake_bob.house_draft AS hda
    LEFT JOIN datalake_bob_clean.submission_progress AS sp
        ON hda.id = sp.id_house_draft
    LEFT JOIN datalake_bob_clean.registrar AS r
        ON hda.registrar = r.id
    LEFT JOIN datalake_ebdb_clean.house AS h
        ON sp.id_external = h.id
    LEFT JOIN datalake_bob_clean.location AS l
        ON hda.id = l.id_house_draft
)

SELECT
    enriched_data.id_draft,
    enriched_data.id_house,
    enriched_data.id_region,
    enriched_data.city,
    enriched_data.id_user_registrant,
    enriched_data.business_context,
    enriched_data.status,
    enriched_data.type,
    enriched_data.ops_team,
    enriched_data.ops_company,
    enriched_data.ops_contact_type,
    enriched_data.ops_contact_channel,
    enriched_data.ts_created,
    enriched_data.ts_updated
FROM
    enriched_data
WHERE
    enriched_data.business_context IS NOT NULL