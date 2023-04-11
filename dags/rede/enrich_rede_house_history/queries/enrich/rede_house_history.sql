WITH partner_agencies_aux AS (
    SELECT
        id_company,
        tag_real_estate_agency AS tag,
        extracted_3p_tag,
        name,
        LAST(lead_status)
        OVER (
            PARTITION BY
                id_company
            ORDER BY
                ts_updated
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS current_status,
        LAST(tag_real_estate_agency)
        OVER (
            PARTITION BY
                id_company
            ORDER BY
                ts_updated
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS current_tag,
        cnpj,
        state AS partner_state,
        ts_updated
    FROM
        datalake_hubspot.company_history
),
extracted_partner_tags AS (
    SELECT
        id_company,
        tag,
        extracted_3p_tag,
        NULLIF(REGEXP_EXTRACT(current_tag, r'\[3(?i:p)(?i:BH)?\-(.+?)\]'), '') AS current_extracted_3p_tag,
        name,
        cnpj,
        partner_state,
        ROW_NUMBER() OVER(
        PARTITION BY
            REPLACE(UPPER(extracted_3p_tag), ' ', '')
        ORDER BY
            ts_updated
        DESC
        ) = 1 AS is_most_recent_for_tag,
        ROW_NUMBER() OVER ( -- Sometimes, more than one company in HubSpot is created with the same cnpj, so we need to deduplicate
            PARTITION BY
                cnpj
            ORDER BY
                current_status IN ('Membro', 'Parceiro', 'Em processo tombamento') DESC, -- First, the ones that are currently members
                current_tag IS NOT NULL DESC, -- Then, the ones with tags
                ts_updated DESC -- Otherwise, most recent
        ) = 1 AS is_most_recent_for_cnpj,
        ROW_NUMBER() OVER(PARTITION BY id_company ORDER BY ts_updated DESC) = 1 AS is_most_recent_for_company
    FROM
        partner_agencies_aux
    QUALIFY
        (is_most_recent_for_tag OR is_most_recent_for_cnpj OR is_most_recent_for_company)
        AND (tag IS NOT NULL or cnpj IS NOT NULL)
),
--- We're getting the most recent row in datalake_hubspot_clean.company for each tag and CNPJ.
--- Since they are merged, extracted_3p_tag only shows up if that row is the most recent company for the given tag. Same for the CNPJ.
partner_agencies AS (
  SELECT
    ept.id_company,
    ept.tag,
    CASE
      WHEN ept.is_most_recent_for_tag THEN ept.extracted_3p_tag
      ELSE NULL
    END AS extracted_3p_tag,
    CASE
      WHEN ept.is_most_recent_for_cnpj THEN ept.cnpj
      ELSE NULL
    END AS cnpj,
    COALESCE(ept.current_extracted_3p_tag, ept.extracted_3p_tag, ept.name) AS partner_3p_supply,
    ept.partner_state
  FROM
    extracted_partner_tags AS ept
),
house_history_aux AS (
    SELECT
        ha.id_house,
        ha.id_external,
        NULLIF(REGEXP_EXTRACT(REPLACE(ha.internal_admin_info, ' ', ''), r'\[3(?i:p)(?i:BH)?\-(.+?)\]'), '') AS extracted_tag,
        UPPER(ha.internal_admin_info) LIKE '%[3P%-%]%' AS is_3p_supply,
        COALESCE(internal_admin_info LIKE '%[3PBH-%]%', FALSE) AS has_3p_bh_in_tag,
        ure.ts_revision
    FROM
        datalake_ebdb_clean.house_aud AS ha
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON ha.rev = ure.id
    QUALIFY
        LAG(ha.internal_admin_info) OVER (PARTITION BY ha.id_house ORDER BY ha.rev) IS DISTINCT FROM ha.internal_admin_info
),
house_history AS (
    SELECT
        id_house,
        pa.id_company AS id_company_hubspot_extracted,
        COALESCE(
            pa.partner_3p_supply,
            h.extracted_tag,
            'Unknown'
        ) AS partner_3p_supply_extracted,
        COALESCE(is_3p_supply, FALSE) AS is_3p_supply,
        COALESCE(pa.partner_state != 'MG', has_3p_bh_in_tag, FALSE) AS is_3p_supply_bh,
        has_3p_bh_in_tag,
        l.id IS NOT NULL AS is_in_supply_processor,
        ts_revision AS ts_status_started
    FROM
        house_history_aux AS h
    LEFT JOIN
        partner_agencies AS pa
            ON UPPER(h.extracted_tag) IN (pa.cnpj, REPLACE(UPPER(pa.extracted_3p_tag), ' ', ''))
    LEFT JOIN
        datalake_brokers_supply_processor.lead_3p AS l
            ON h.id_external = l.uuid_lead
),
sale_united AS (
    SELECT
        lbca.id_house,
        NULL::BIGINT AS id_company_hubspot_extracted,
        'LBC' AS source,
        NULL::STRING AS partner_3p_supply_extracted,
        lbca.ownership = 'THIRD_PARTY' AS is_3p_supply,
        NULL::BOOLEAN AS is_3p_supply_bh,
        NULL::BOOLEAN AS is_in_supply_processor,
        NULL::BOOLEAN AS has_3p_bh_in_tag,
        CASE -- Some migrations incorrectly set the revision timestamp to the year 2610. We're fixing them here.
            WHEN DATE(ure.ts_revision) = '2610-10-12' THEN '2022-10-25T23:53:18.764+0000'::TIMESTAMP
            ELSE ure.ts_revision
        END AS ts_status_started
    FROM
        datalake_ebdb_clean.listing_business_context_aud AS lbca
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON lbca.rev = ure.id
    WHERE
        lbca.business_context = 'SALE'
        AND ure.ts_revision >= '2022-08-01' -- We won't trust revisions before this date, since the column ownership had just been added.
        AND DATE(ure.ts_revision) != '2610-10-07'
    QUALIFY
        LAG(lbca.ownership) OVER (PARTITION BY lbca.id_listing_business_context ORDER BY lbca.rev) IS DISTINCT FROM lbca.ownership
    UNION ALL
    SELECT
        id_house,
        id_company_hubspot_extracted,
        'H' AS source,
        partner_3p_supply_extracted,
        is_3p_supply,
        is_3p_supply_bh,
        is_in_supply_processor,
        has_3p_bh_in_tag,
        ts_status_started
    FROM
        house_history
),
sale_fetching_last AS (
    SELECT
        su.id_house,
        LAST(su.id_company_hubspot_extracted, TRUE) OVER (PARTITION BY su.id_house ORDER BY su.ts_status_started) AS id_company_hubspot_extracted,
        LAST(su.partner_3p_supply_extracted, TRUE) OVER (PARTITION BY su.id_house ORDER BY su.ts_status_started) AS partner_3p_supply_extracted,
        COALESCE(
            LAST( -- Before 2023, if the house was 3P, we can assume it was 3P ForSale. But after 2023, we can't, since the house could have been 3P ForRent.
                CASE WHEN su.source = 'H' AND (su.ts_status_started < '2023-01-01') THEN su.is_3p_supply END, TRUE
            ) OVER (
                PARTITION BY
                    su.id_house
                ORDER BY su.ts_status_started
            ),
            FALSE
        ) AS is_3p_supply_house_aud,
        LAST(
            CASE WHEN su.source = 'LBC' THEN su.is_3p_supply END, TRUE
        ) OVER (
            PARTITION BY
                su.id_house
            ORDER BY
                su.ts_status_started
        ) AS is_3p_supply_lbc_aud,
        LAST(su.is_3p_supply_bh, TRUE) OVER (PARTITION BY su.id_house ORDER BY su.ts_status_started) AS is_3p_supply_bh,
        LAST(su.is_in_supply_processor, TRUE) OVER (PARTITION BY su.id_house ORDER BY su.ts_status_started) AS is_in_supply_processor,
        LAST(su.has_3p_bh_in_tag, TRUE) OVER (PARTITION BY su.id_house ORDER BY su.ts_status_started) AS has_3p_bh_in_tag,
        su.ts_status_started
    FROM
        sale_united AS su
),
sale_final AS (
    SELECT
        sfl.id_house,
        -- Business rules to consider a listing Sale 3P supply:
        -- 3P BH was migrated incorrectly to the ownership column, so we will consider the tag instead (until 2023).
        -- We prioritize whatever came from listing_business_context, then house
        -- If the house was inputed manually, we will consider the tag (until 2023)
        CASE
            WHEN ( 
                (has_3p_bh_in_tag AND sfl.ts_status_started < '2023-01-01')
                OR COALESCE(sfl.is_3p_supply_lbc_aud, sfl.is_3p_supply_house_aud)
                OR (NOT sfl.is_in_supply_processor AND sfl.is_3p_supply_house_aud AND sfl.ts_status_started < '2023-01-01')
            ) THEN sfl.id_company_hubspot_extracted
        END AS id_company_hubspot,
        'SALE' AS business_context,
        CASE
            WHEN (
                (has_3p_bh_in_tag AND sfl.ts_status_started < '2023-01-01')
                OR COALESCE(sfl.is_3p_supply_lbc_aud, sfl.is_3p_supply_house_aud)
                OR (NOT sfl.is_in_supply_processor AND sfl.is_3p_supply_house_aud AND sfl.ts_status_started < '2023-01-01')
            ) THEN partner_3p_supply_extracted
        END AS partner_3p_supply,
        (
            (has_3p_bh_in_tag AND sfl.ts_status_started < '2023-01-01')
            OR COALESCE(sfl.is_3p_supply_lbc_aud, sfl.is_3p_supply_house_aud)
            OR (NOT sfl.is_in_supply_processor AND sfl.is_3p_supply_house_aud AND sfl.ts_status_started < '2023-01-01')
        ) AS is_3p_supply,
        CASE
            WHEN (
                (has_3p_bh_in_tag AND sfl.ts_status_started < '2023-01-01')
                OR COALESCE(sfl.is_3p_supply_lbc_aud, sfl.is_3p_supply_house_aud)
                OR (NOT sfl.is_in_supply_processor AND sfl.is_3p_supply_house_aud AND sfl.ts_status_started < '2023-01-01')
            ) THEN is_3p_supply_bh
            ELSE FALSE
        END AS is_3p_supply_bh,
        sfl.ts_status_started
    FROM
        sale_fetching_last AS sfl
    QUALIFY
        LAG(is_3p_supply) OVER(PARTITION BY id_house ORDER BY ts_status_started) IS DISTINCT FROM is_3p_supply
        OR LAG(id_company_hubspot) OVER(PARTITION BY id_house ORDER BY ts_status_started) IS DISTINCT FROM id_company_hubspot
        OR LAG(partner_3p_supply) OVER(PARTITION BY id_house ORDER BY ts_status_started) IS DISTINCT FROM partner_3p_supply
),
rent_united AS (
    (SELECT
        lbc.id_house,
        NULL::BIGINT AS id_company_hubspot_extracted,
        NULL::STRING AS partner_3p_supply_extracted,
        lrma.rental_administrator = 'THIRD_PARTY' AS is_3p_supply,
        ure.ts_revision AS ts_status_started
    FROM
        datalake_ebdb_clean.listing_rent_model_aud AS lrma
    JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id = lrma.id_listing_business_context
            AND lbc.business_context = 'RENT'
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON lrma.rev = ure.id
    QUALIFY
        LAG(lrma.rental_administrator) OVER (PARTITION BY lrma.id_listing_business_context ORDER BY lrma.rev) IS DISTINCT FROM lrma.rental_administrator)
    UNION ALL
    SELECT
        id_house,
        id_company_hubspot_extracted,
        partner_3p_supply_extracted,
        NULL AS is_3p_supply,
        ts_status_started
    FROM
        house_history
),
rent_fetching_last AS (
    SELECT
        id_house,
        LAST(id_company_hubspot_extracted, TRUE) OVER (PARTITION BY id_house ORDER BY ts_status_started) AS id_company_hubspot_extracted,
        LAST(partner_3p_supply_extracted, TRUE) OVER (PARTITION BY id_house ORDER BY ts_status_started) AS partner_3p_supply_extracted,
        COALESCE(LAST(is_3p_supply, TRUE) OVER (
            PARTITION BY
                id_house
            ORDER BY
                ts_status_started
        ), FALSE) AS is_3p_supply,
        ts_status_started
    FROM
        rent_united
),
rent_final AS (
    SELECT
        id_house,
        CASE
            WHEN is_3p_supply THEN id_company_hubspot_extracted
        END AS id_company_hubspot,
        'RENT' AS business_context,
        CASE
            WHEN is_3p_supply THEN partner_3p_supply_extracted
        END AS partner_3p_supply,
        is_3p_supply,
        ts_status_started
    FROM
        rent_fetching_last
    QUALIFY
        LAG(is_3p_supply) OVER(PARTITION BY id_house ORDER BY ts_status_started) IS DISTINCT FROM is_3p_supply
        OR LAG(id_company_hubspot) OVER(PARTITION BY id_house ORDER BY ts_status_started) IS DISTINCT FROM id_company_hubspot
        OR LAG(partner_3p_supply) OVER(PARTITION BY id_house ORDER BY ts_status_started) IS DISTINCT FROM partner_3p_supply
)
SELECT
    id_house,
    id_company_hubspot,
    business_context,
    partner_3p_supply,
    is_3p_supply,
    ts_status_started,
    LEAD(ts_status_started) OVER(PARTITION BY id_house ORDER BY ts_status_started) AS ts_status_ended
FROM
    sale_final
UNION ALL
SELECT
    id_house,
    id_company_hubspot,
    business_context,
    partner_3p_supply,
    is_3p_supply,
    ts_status_started,
    LEAD(ts_status_started) OVER(PARTITION BY id_house ORDER BY ts_status_started) AS ts_status_ended
FROM
    rent_final
