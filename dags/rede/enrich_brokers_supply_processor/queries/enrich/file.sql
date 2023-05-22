WITH partner_agencies_aux AS (
    SELECT
        ch.id_company AS id_company_hubspot,
        c.tag_real_estate_agency AS current_tag,
        c.lead_status AS current_status,
        ch.cnpj,
        ch.ts_updated
    FROM
        datalake_hubspot.company_history AS ch
    JOIN
        datalake_hubspot.company AS c
            ON ch.id_company = c.id_company
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                ch.cnpj
            ORDER BY
                NOT c.is_archived DESC, -- Give preference to non-archived companies when we find duplicates
                current_status IN ('Membro', 'Parceiro', 'Em processo tombamento') DESC,  -- Then, members
                current_tag IS NOT NULL DESC, -- Then, those that have a tag
                ch.ts_updated DESC -- Finally, most recent
        ) = 1
        AND ch.cnpj IS NOT NULL
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