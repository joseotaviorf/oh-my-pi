WITH origin_newer_leads AS (
    WITH origin_newer_leads_raw AS (
        SELECT
            l.id AS id_lead,
            SUBSTRING(
                l.extra_infos,
                instr(l.extra_infos, 'id_origin_lead') +
                  IF(l.extra_infos LIKE '%id_origin_lead=%', 15, 17) -- 15 for `id_origin_lead=ID` / 17 for `id_origin_lead = ID`
            ) as id_origin_lead_raw
        FROM
            datalake_ebdb_clean.lead l
        WHERE l.extra_infos LIKE '%id_origin_lead%'
    )
    SELECT
        id_lead,
        SUBSTRING(
            REPLACE(CONCAT(id_origin_lead_raw, ';'), ' ', ';'),
            1,
            instr(REPLACE(CONCAT(id_origin_lead_raw, ';'), ' ', ';'), ';') - 1
        ) id_origin_lead
    FROM origin_newer_leads_raw
)
SELECT
	l.id,
    CASE
        -- Retrieving original lead id in newer leads
        WHEN onl.id_lead IS NOT NULL
            THEN id_origin_lead
        -- Retrieving original lead id in older leads
        WHEN SUBSTRING_INDEX(l.extra_infos,';',1) RLIKE '^-?[0-9]+$'
            THEN SUBSTRING_INDEX(l.extra_infos,';',1)
        ELSE
            -- No pattern inside l.extra_infos matched reprocessed leads
            NULL
    END AS id_origin_lead
FROM
    datalake_ebdb_clean.lead l
LEFT JOIN origin_newer_leads onl
    ON onl.id_lead = l.id
WHERE
    l.source = 'Reprocessado' AND COALESCE(l.extra_infos,'') <> ''