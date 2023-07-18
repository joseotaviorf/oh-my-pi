WITH files_with_company AS (
    SELECT
        f.id,
        f.id_partner,
        l.uuid_company,
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
            AND l.uuid_company IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY f.id ORDER BY f.ts_updated DESC, l.ts_updated DESC) = 1
)
SELECT
    fwc.id,
    fwc.id_partner,
    hc.id_company AS id_company_hubspot,
    fwc.uuid_company,
    fwc.hash,
    fwc.file_name,
    fwc.type,
    fwc.url,
    fwc.file_byte,
    fwc.version,
    LAG(fwc.ts_created) OVER (
        PARTITION BY
            COALESCE(fwc.uuid_company, SPLIT(fwc.file_name, '_dedup_')[0])
        ORDER BY
            fwc.ts_created
    ) AS ts_previous_file_sent_by_agency,
    fwc.ts_created,
    fwc.ts_updated
FROM
    files_with_company AS fwc
LEFT JOIN
    datalake_hubspot.company AS hc
        ON hc.uuid_company = fwc.uuid_company