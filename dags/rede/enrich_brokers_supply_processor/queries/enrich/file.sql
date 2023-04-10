WITH partner_agencies_aux AS (
    SELECT
        id_company AS id_company_hubspot,
        LAST(NULLIF(GET_JSON_OBJECT(properties, '$.tag_imobiliarias'), '')) OVER (PARTITION BY id_company ORDER BY ts_updated ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS current_tag,
        LAST(NULLIF(GET_JSON_OBJECT(properties, '$.hs_lead_status'), '')) OVER (PARTITION BY id_company ORDER BY ts_updated ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS current_status,
        NULLIF(REGEXP_REPLACE(GET_JSON_OBJECT(properties, '$.cnpj'), '[^0-9]', ''), '') AS cnpj,
        ts_updated
    FROM
        datalake_hubspot_clean.company
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                cnpj
            ORDER BY
                current_status IN ('Membro', 'Parceiro', 'Em processo tombamento') DESC, 
                current_tag IS NOT NULL DESC,
                ts_updated DESC
        ) = 1
        AND cnpj IS NOT NULL
),
files_with_company AS (
    SELECT
        f.id,
        f.id_partner,
        l.cnpj,
        f.hash,
        f.file_name,
        f.type,
        f.url,
        f.file_byte,
        f.version,
        f.ts_created,
        f.ts_updated
    FROM
        datalake_brokers_supply_processor_clean.file AS f
    LEFT JOIN
        datalake_brokers_supply_processor_clean.business_context_detail AS bcd
            ON bcd.id_file = f.id
    LEFT JOIN
        datalake_brokers_supply_processor_clean.lead_3p AS l
            ON bcd.id_lead = l.id
            AND l.cnpj != 'Não informado'
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY f.id ORDER BY f.ts_updated DESC, l.ts_updated DESC) = 1
)
SELECT
    fwc.id,
    fwc.id_partner,
    pa.id_company_hubspot,
    fwc.hash,
    fwc.file_name,
    fwc.type,
    fwc.url,
    fwc.file_byte,
    fwc.version,
    LAG(fwc.ts_created) OVER (
        PARTITION BY
            COALESCE(pa.id_company_hubspot, SPLIT(fwc.file_name, '_dedup_')[0])
        ORDER BY
            fwc.ts_created
    ) AS ts_previous_file_sent_by_agency,
    fwc.ts_created,
    fwc.ts_updated
FROM
    files_with_company AS fwc
LEFT JOIN
    partner_agencies_aux AS pa
        ON pa.cnpj = fwc.cnpj