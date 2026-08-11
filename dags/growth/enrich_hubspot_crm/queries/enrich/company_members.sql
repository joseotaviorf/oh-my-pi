WITH company_ranked AS (
    SELECT
        c.id_company,
        c.id_hubspot_owner,
        c.cnpj,
        REGEXP_REPLACE(c.creci, '[^a-zA-Z0-9]', '') AS creci,
        c.company_cluster,
        c.name AS company_name,
        c.cluster_performance AS company_cluster_performance,
        c.crm,
        c.extracted_3p_tag,
        c.member_category,
        c.sale_lead_status,
        c.is_flagged_as_leadgen,
        TRUE AS has_3p_access_control,
        c.ts_created,
        c.ts_updated,
        c.year,
        c.month,
        c.day,
        ROW_NUMBER() OVER(PARTITION BY c.cnpj ORDER BY c.ts_updated DESC) AS rn
    FROM
        datalake_hubspot.company AS c
    WHERE
        c.has_been_sale_member
        AND NOT(c.is_archived)
        AND NOT(c.is_merged_into_other_company)
)
SELECT
    id_company,
    id_hubspot_owner,
    cnpj,
    creci,
    company_cluster,
    company_name,
    company_cluster_performance,
    crm,
    extracted_3p_tag,
    member_category,
    sale_lead_status,
    is_flagged_as_leadgen,
    has_3p_access_control,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    company_ranked
WHERE
    rn = 1
