WITH partner_agencies_aux AS (
    SELECT
        id_company AS id_company_hubspot,
        NULLIF(REGEXP_REPLACE(GET_JSON_OBJECT(properties, '$.cnpj'), '[^0-9]', ''), '') AS cnpj,
        ts_updated
    FROM
        datalake_hubspot_clean.company
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY cnpj ORDER BY ts_updated DESC) = 1
        AND cnpj IS NOT NULL
),
files_with_company AS (
    SELECT
        f.id,
        f.id_partner,
        pa.id_company_hubspot,
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
        datalake_brokers_supply_processor_clean.lead_3p AS l
            ON f.id = l.id_file
            AND l.cnpj != 'Não informado'
    LEFT JOIN
        partner_agencies_aux AS pa
            ON pa.cnpj = l.cnpj
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY f.id ORDER BY f.ts_updated DESC, l.ts_updated DESC) = 1
)
SELECT
    fwc.id,
    fwc.id_partner,
    fwc.id_company_hubspot,
    fwc.hash,
    fwc.file_name,
    fwc.type,
    fwc.url,
    fwc.file_byte,
    fwc.version,
    LAG(fwc.ts_created) OVER (
        PARTITION BY
            COALESCE(fwc.id_company_hubspot, SPLIT(fwc.file_name, '_dedup_')[0])
        ORDER BY
            fwc.ts_created
    ) AS ts_previous_file_sent_by_agency,
    fwc.ts_created,
    fwc.ts_updated
FROM
    files_with_company AS fwc
