-- ponytail: point-in-time store of agent attributes the Type-1 `agent` dim overwrites;
-- fact_agent_daily COALESCEs these over current-dim values. CURRENT_DATE snapshot is
-- deliberately NOT backfillable — reprocessing a past day stamps it with today's values.
-- Do not "fix" by rebuilding from `agent` (loses history). Proper fix = SCD-2 upstream.
SELECT
    MD5(CONCAT(id_agent, CURRENT_DATE)) AS id_agent_daily,
    id_agent,
    id_agent_data,
    id_partner,
    id_user,
    uuid_company,
    uuid_agent,
    uuid_person,
    creci,
    creci_uf,
    affiliation_type,
    company_product_name,
    profile,
    is_allow_demand_sale,
    is_allow_demand_rent,
    is_passive_lead_receiver,
    is_1p_partnership,
    is_3p_partnership,
    ts_created,
    CURRENT_DATE AS dt_ref,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    datalake_agent_accreditation.agent
WHERE
    status = 'ACTIVE'
    OR (status = 'INACTIVE' AND TIMESTAMPDIFF(DAY, DATE(ts_updated), CURRENT_DATE) < 1)
