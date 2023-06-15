WITH merged_companies_aux AS (
    SELECT
        ids_merged_companies
    FROM
        datalake_hubspot.company_history
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_company ORDER BY ts_updated DESC) = 1
),
merged_companies AS (
    SELECT
        EXPLODE(ids_merged_companies) AS id_merged_company
    FROM
        merged_companies_aux
),
hubspot_companies AS (
    SELECT
        id_company,
        cnpj,
        ts_updated,
        LAST(sale_lead_status)
        OVER (
            PARTITION BY
                id_company
            ORDER BY
                ts_updated
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS current_sale_status,
        LAST(rent_lead_status)
        OVER (
            PARTITION BY
                id_company
            ORDER BY
                ts_updated
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS current_rent_status,
        LAST(tag_real_estate_agency)
        OVER (
            PARTITION BY
                id_company
            ORDER BY
                ts_updated
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS current_tag,
        LAST(is_archived)
        OVER (
            PARTITION BY
                id_company
            ORDER BY
                ts_updated
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS is_currently_archived
    FROM
        datalake_hubspot.company_history
),
company_matches AS (
    SELECT
        c.uuid_company,
        ch.id_company AS id_company_hubspot
    FROM
        datalake_company_clean.company_document AS cd
    JOIN
        datalake_company_clean.company AS c
            ON cd.id_company = c.id
    JOIN
        datalake_company_clean.document AS d
            ON cd.id_document = d.id
            AND d.document_type = 'CNPJ'
    JOIN
        datalake_company_clean.company_product AS cp
            ON c.id = cp.id_company
            AND cp.id_product = 27
    JOIN
        hubspot_companies AS ch
            ON d.identification_number = ch.cnpj
    LEFT JOIN
        merged_companies AS mc
            ON ch.id_company = mc.id_merged_company
    QUALIFY
        ROW_NUMBER() OVER (
        PARTITION BY
            d.identification_number
        ORDER BY
            NOT ch.is_currently_archived AND mc.id_merged_company IS NULL DESC, -- First, not archived nor merged
            (
                ch.current_sale_status IN ('Membro', 'Parceiro', 'Em processo tombamento')
                OR ch.current_rent_status IN ('Membro', 'Parceiro', 'Em processo tombamento')
            ) DESC, -- Then, the ones that are currently members
            ch.current_tag IS NOT NULL DESC, -- Then, the ones with tags
            ch.ts_updated DESC -- Otherwise, most recent
        ) = 1
)
SELECT
    ch.id_company,
    cm.uuid_company,
    ch.id_hubspot_owner,
    ch.id_hubspot_team,
    ch.id_parent_company,
    ch.ids_merged_companies,
    ch.fields_of_business,
    ch.address,
    ch.zip_code,
    ch.city,
    ch.state,
    ch.country,
    ch.domain,
    ch.e_mail,
    ch.hs_analytics_source,
    ch.hs_analytics_source_data_1,
    ch.hs_analytics_source_data_2,
    ch.industry,
    ch.inside_sales,
    ch.life_cycle_stage,
    ch.mkt_campain,
    ch.mkt_channel,
    ch.mkt_content,
    ch.mkt_medium,
    ch.mkt_origin,
    ch.mkt_source,
    ch.discard_reason,
    ch.unified_discard_reasons,
    ch.name,
    ch.tag_real_estate_agency,
    ch.extracted_3p_tag,
    ch.member_type,
    ch.member_category,
    -- The row below will be duplicated with the row above until June 7th, so we give time for people to update their queries
    -- After that, member_category will be deprecated and we will remove the row above
    ch.sale_member_category,
    ch.rent_member_category,
    ch.member_category_history,
    -- The row below will be duplicated with the row above until June 7th, so we give time for people to update their queries
    -- After that, member_category_history will be deprecated and we will remove the row above
    ch.sale_member_category_history,
    ch.rent_member_category_history,
    ch.lead_origin,
    ch.phone,
    ch.partnership_type,
    ch.first_conversion_event_name,
    ch.hs_analytics_first_touch_converting_campaign,
    ch.crm,
    ch.partner_agencies,
    ch.advertising_portals,
    ch.rental_guarantee_solutions,
    ch.real_estate_agency_focus,
    ch.financing_banks,
    ch.cnpj,
    ch.creci,
    ch.products_of_interest,
    CASE
        WHEN mc.id_merged_company IS NOT NULL OR ch.is_archived THEN 'Archived'
        ELSE ch.lead_status
    END AS lead_status,
    -- The row below will be duplicated with the row above until June 7th, so we give time for people to update their queries
    -- After that, lead_status will be deprecated and we will remove the row above
    CASE
        WHEN mc.id_merged_company IS NOT NULL OR ch.is_archived THEN 'Archived'
        ELSE ch.sale_lead_status
    END AS sale_lead_status,
    CASE
        WHEN mc.id_merged_company IS NOT NULL OR ch.is_archived THEN 'Archived'
        ELSE ch.rent_lead_status
    END AS rent_lead_status,
    ch.lead_status_history,
    -- The row below will be duplicated with the row above until June 7th, so we give time for people to update their queries
    -- After that, lead_status will be deprecated and we will remove the row above
    ch.sale_lead_status_history,
    ch.rent_lead_status_history,
    ch.num_associated_deals,
    ch.num_associated_contacts,
    ch.monthly_average_new_rental_contracts,
    ch.num_managers,
    ch.num_managed_properties,
    ch.num_monthly_leads,
    ch.average_sale_property_ticket,
    ch.average_rent_property_ticket,
    ch.monthly_repayment_volume_in_real,
    ch.monthly_sale_volume_in_real,
    ch.num_real_estate_agents,
    ch.num_properties_for_sale,
    ch.num_properties_for_rent,
    COALESCE(
        ARRAY_CONTAINS(sale_lead_status_history.value, 'Membro')
        OR ARRAY_CONTAINS(sale_lead_status_history.value, 'Parceiro'),
        FALSE
    ) AS has_been_sale_member,
    COALESCE(
        ARRAY_CONTAINS(rent_lead_status_history.value, 'Membro')
        OR ARRAY_CONTAINS(rent_lead_status_history.value, 'Parceiro'),
        FALSE
    ) AS has_been_rent_member,
    ch.has_crm,
    ch.has_property_advertisement_online,
    ch.is_correspondent_bank,
    ch.is_lost,
    ch.has_financing,
    ch.is_for_sale,
    ch.is_for_rent,
    ch.has_partnerships_with_other_agencies,
    ch.is_natural_person,
    ch.is_juridical_person,
    mc.id_merged_company IS NOT NULL OR ch.is_archived AS is_archived,
    mc.id_merged_company IS NOT NULL AS is_merged_into_other_company,
    ch.ts_first_conversion,
    ch.ts_recent_deal_close,
    ch.ts_hubspot_owner_assigned,
    ch.ts_last_logged_call,
    ch.ts_notes_last_updated,
    IF(mc.id_merged_company IS NOT NULL, ch.ts_updated, ch.ts_archived) AS ts_archived,
    ch.ts_created,
    ch.ts_updated,
    ch.year,
    ch.month,
    ch.day
FROM
    datalake_hubspot.company_history AS ch
LEFT JOIN
    company_matches AS cm
        ON ch.id_company = cm.id_company_hubspot
LEFT JOIN
    merged_companies AS mc
        ON ch.id_company = mc.id_merged_company
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY ch.id_company ORDER BY ch.ts_updated DESC) = 1