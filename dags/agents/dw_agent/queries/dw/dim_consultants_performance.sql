WITH
base_p AS (
    SELECT
        DATE(dim_house_listing.ts_publication) AS dt_publication,
        dim_house_listing.id_house AS sk_house,
        dim_house_listing.sk_house_listing,
        dim_house_listing.listing_category_start,
        owner.sk_user AS sk_owner,
        asp.sk_user AS sk_user_consultant,
        MAX_BY(dhl_asp_previous.sk_house_listing, dhl_asp_previous.ts_publication) AS previous_asp_listing
    FROM dw_public.dim_house_listing
    INNER JOIN dw_public.fact_house_listings fhl
        ON fhl.sk_house_listing = dim_house_listing.sk_house_listing
    LEFT JOIN datalake_gsheets_clean.asp_consultants_allocation AS asp_alloc
        ON fhl.sk_owner % 100 BETWEEN asp_alloc.range_start AND asp_alloc.range_end
        AND dim_house_listing.ts_publication BETWEEN asp_alloc.dt_start AND asp_alloc.dt_end
        AND asp_alloc.team LIKE '%' || dim_house_listing.listing_category_start || '%'
    LEFT JOIN dw_public.dim_user asp
        ON asp_alloc.id_user = asp.sk_user
    LEFT JOIN dw_public.dim_user owner
        ON owner.sk_user = fhl.sk_owner
    LEFT JOIN datalake_ebdb_clean.user_pro_owner pp_multi
        ON owner.sk_user = pp_multi.id_user
        AND dim_house_listing.ts_publication > DATE(pp_multi.ts_created)
    LEFT JOIN dw_public.fact_house_listings AS fhl_asp_previous
        ON fhl_asp_previous.sk_owner = fhl.sk_owner
        AND fhl_asp_previous.sk_house_listing <> fhl.sk_house_listing
    LEFT JOIN dw_public.dim_house_listing dhl_asp_previous
        ON dhl_asp_previous.sk_house_listing = fhl_asp_previous.sk_house_listing
        AND dhl_asp_previous.ts_publication < dim_house_listing.ts_publication
        AND dhl_asp_previous.consultant_type = 'ASP'
    WHERE dim_house_listing.consultant_type = 'CIQ_FULL'
        AND dim_house_listing.ts_publication > DATE('2023-07-15')
        AND dim_house_listing.country_code IN ('BR', 'Undefined')
        AND pp_multi.id_user IS NULL
    GROUP BY 1, 2, 3, 4, 5, 6
),
alocacao_imoveis_ciq_atuacao_asp AS (
    SELECT
        base_p.dt_publication,
        base_p.sk_house,
        base_p.sk_house_listing,
        base_p.listing_category_start,
        base_p.sk_owner,
        COALESCE(asp_alloc.id_user, base_p.sk_user_consultant) AS sk_user_consultant
    FROM base_p
    LEFT JOIN dw_public.fact_house_listings fhl
        ON fhl.sk_house_listing = base_p.previous_asp_listing
    LEFT JOIN datalake_gsheets_clean.asp_consultants_allocation AS asp_alloc
        ON asp_alloc.id_user = fhl.sk_user_consultant
        AND base_p.dt_publication BETWEEN asp_alloc.dt_start AND asp_alloc.dt_end
),
messages_raw AS (
    SELECT
        mes.agent_email,
        COALESCE(
            ARRAY_MIN(sp.phones),
            CASE
                WHEN mes.prospect_phone IS NOT NULL AND mes.prospect_phone LIKE '+%' THEN mes.prospect_phone
                WHEN mes.prospect_phone IS NOT NULL THEN '+' || mes.prospect_phone
            END
        ) AS prospect_phone,
        LOWER(ARRAY_MIN(sp.emails)) AS prospect_email,
        DATEADD(HOUR, -3, mes.ts_created) AS ts_created
    FROM datalake_sirena.messages mes
    LEFT JOIN datalake_sirena_clean.prospects sp
        ON sp.id = mes.id_prospect
    WHERE template IN (
    'ab20b849-89d4-4d96-879c-cb12ad97d4d8',
    '59624c8b-ed76-411f-9b07-81a3d6c17c2a',
    '16474e7f-edc3-4cde-9f1a-75221211068e',
    '9983079a-32c8-463c-8b46-4f612b8e9227',
    '2177c65c-3497-4571-ae06-cbfe5b875cdc',
    'd5bd6e8d-c18e-41bb-a70a-683f691772fd',
    '1d781a4e-6a4e-4f3a-81b7-5a06502826e0',
    '5def1a76-2a4f-433b-84b4-795acc3462db',
    '84dd405b-75b3-4f6f-84fe-d11dc252fa26',
    '4cb0e879-92f1-4e75-943e-3df1c0da4340',
    '38d635c0-f4e3-4e6e-b322-1b54ca1fcae4',
    '1d781a4e-6a4e-4f3a-81b7-5a06502826e0',
    'adc90940-b8a1-413f-88d2-0bab7c604318',
    '6f54c5d9-e90c-4525-993b-b3f39da82638',
    'abf93e8e-0a4e-4d29-ab9b-cec288735d43',
    '48860f50-bd48-4b60-9bbe-d9f1b847b5bf',
    'b3f52409-83e5-432c-a848-d3a64e4801ae',
    '7fa08498-c8cb-45cf-9f80-372e86ac2292',
    '27876867-d286-4436-b31c-2f8604e9f98d',
    '55c61954-8619-4499-b948-346bb9d27447',
    'c230a089-312c-4efb-bea9-ceb0954c30eb',
    '9f0ad82f-9ec6-4033-9333-7416ec6547f1',
    'cd31a9fd-9631-403f-8139-b41c80e96bfc',
    '28682bc9-73f0-458d-a5e4-28df5162210b',
    '4d1710e0-94bc-481a-98a2-84a90aee3d6e',
    'f7828292-3919-4a98-a92b-d32208efe76b',
    '775197d0-cfc0-4a22-b385-708f25ba582e',
    '6903d488-39ef-4660-8022-7cd79dc83bb3',
    '69cff50b-7d22-4d35-8594-4af5f62c6e13',
    'e0e6dff7-19fb-4b5d-93c1-32fcc0f185dd',
    '021583b7-c0c2-4305-b94e-130cf170dc5a',
    'd927ec0b-3e64-4097-a814-f088042fa36f',
    'd62309bf-f820-43fc-9107-589a7ecc9ce1',
    'cc5eea60-9d2b-465a-ac02-b6006d851d6d',
    'f18f6266-242b-4070-bf38-f0ccf9f1a35a',
    '7fc8f99d-3e7e-4ba4-8c70-e6f6390b3656',
    'ba0a6e8e-bc34-419e-8780-160533fc67a8',
    '326e08f5-76ae-45f9-9637-3aef1d92b4ca',
    'e88d5849-d8c0-42f1-8982-8cb8bf1b3ddf',
    '4eaa8efa-e6a5-4976-b48c-ffd268f8e1b0',
    '4eaa8efa-e6a5-4976-b48c-ffd268f8e1b0',
    '919f579f-6088-4a1e-8b14-925da04f1094',
    '969f81d3-13c5-406c-9efc-89508e233d33',
    'a4c417c9-4701-46a6-ad1d-0c4bc3d9f99d',
    'e64dec06-cdd7-4d64-be09-687765f71669',
    'bdd51a33-d1df-4e36-a49c-2ef1c667f82b',
    '0cff8b17-f646-4828-9aa1-b1821b3a62f4',
    'fdb8140b-4034-4346-a699-11dd0596ffd0',
    '5e95db3f-9858-459b-9a56-6dc67ad7869d',
    '655f0eca-b3d7-49c9-8296-09bb71c1b675',
    '00461bab-decb-4b63-b82d-9114850a61c6',
    '327a82b0-d265-414d-84be-537a0c997640',
    'f55bd4cc-7ec2-4fa0-b592-606df5757a79',
    '88aed870-479e-4bcb-909c-d41251346180',
    '52bbce59-8311-4236-9e84-06b856a44610',
    '9723088a-9aca-41d5-a987-6b025c339af8',
    '02c1de69-3b7f-45df-8b43-1521d9228bed',
    '00461bab-decb-4b63-b82d-9114850a61c6',
    '5be83b3c-fdf5-4abc-a823-1a3610b22f7f',
    '3c355446-866f-4778-8cea-b235a51bf119',
    '68583987-e5f1-4939-8b48-8d1eccb17026',
    '22b50c01-1ee5-462a-8adc-284c6f0cef3c',
    'afa030d6-64ec-4eff-9876-cb06a3338004',
    '63c40f6f-8932-44de-bc66-e005b9625595',
    'c567ad7e-7f13-456f-88bf-90e8da87a3f8',
    '0df738d0-8756-4e98-b208-a63a048482e2',
    '8795748b-0279-4b55-b511-00e66d2543e8',
    'ad154040-4cdc-4024-8b48-a1047a3513d3',
    '7bcdf466-3e92-41b4-b5b8-815e0e6e5472',
    '9d2eb05b-dcfd-46ec-a72e-8b43b02196f3',
    '08df1fd7-c786-4292-aa93-cdb77b6755a3',
    '34d62101-6ea0-4d21-b12a-20488515869e',
    'e2049600-a781-42e9-9f09-c8c35313a232',
    '058578d2-c323-4d2e-b859-4946fee5d340',
    '6f9e47c5-6f7a-49b5-91d4-f78e42f86dde',
    'c0ba1d3c-6de5-46d3-84f4-da947d476f61',
    '83dd51df-a01f-44e2-8a6c-7745ea4ee0ad',
    '6eed6d7c-3c5e-427b-a354-6be67c3b009e',
    'fc7f7e4b-4d77-4653-a6aa-62f496a6a5c1',
    '06f857e4-53cc-417e-8f9b-d868e0d65546',
    '43accecb-35d5-4fbe-851f-117379d1236f',
    'f68f6e42-c4db-47c8-9794-291fa16f23b1'
    )
),
messages AS (
    SELECT
        dim_house_listing.id_house,
        fl.sk_house_listing,
        fl.sk_owner,
        MIN(mes.ts_created) AS min_ts_created
    FROM messages_raw mes
    INNER JOIN datalake_sirena_clean.agents a
        ON a.email = mes.agent_email
        AND a.id_group = '619533269674e200180bc729' -- QuintoAndar Assessor
    INNER JOIN dw_public.dim_user owner
        ON (owner.telefone_principal = mes.prospect_phone OR owner.email = mes.prospect_email)
        AND owner.tem_imovel <> '0'
    INNER JOIN dw_public.fact_house_listings fl
        ON fl.sk_owner = owner.sk_user
    INNER JOIN dw_public.dim_house_listing
        ON fl.sk_house_listing = dim_house_listing.sk_house_listing
        AND mes.ts_created > dim_house_listing.ts_listing_version_start
        AND (mes.ts_created < dim_house_listing.ts_listing_version_end OR dim_house_listing.is_last_version)
        AND dim_house_listing.version > 0
    LEFT JOIN datalake_offboarding.contract_termination ct
        ON ct.id_house_listing = dim_house_listing.sk_house_listing - 1
        AND dim_house_listing.is_early_demand
        AND ct.status <> 'CANCELED'
    WHERE COALESCE(ct.ts_analyst_annulment_input, dim_house_listing.ts_publication) > DATEADD(DAY, -30, DATE_TRUNC('MM', CURRENT_DATE())
    AND listing_category_start IN ('First Listing', 'Re-Listing', 'Recovered')
    GROUP BY 1, 2, 3
),
entry_condition AS (
    SELECT
        aud.id_house,
        aud.rev,
        aat.name AS key_location,
        ts_revision
    FROM datalake_ebdb_clean.access_type_aud aud
    LEFT JOIN datalake_ebdb_clean.access_authorization_type aat
        ON aat.id = aud.id_authorization
    INNER JOIN datalake_ebdb_user.user_revision_entity r
        ON r.id = aud.rev
),
predicted_price AS (
    SELECT
        dpr_aud.id_house,
        dpr_aud.p_90,
        COALESCE(ts_revision, dpr.ts_created) AS ts_start,
        COALESCE(LEAD(ts_revision) OVER (PARTITION BY dpr_aud.id_house ORDER BY ts_revision), CURRENT_DATE) AS ts_end
    FROM datalake_ebdb_clean.house_predicted_price dpr
    LEFT JOIN datalake_ebdb_clean.house_predicted_price_aud dpr_aud
        ON dpr.id_house = dpr_aud.id_house
        AND dpr.business_context = dpr_aud.business_context
    LEFT JOIN datalake_ebdb_user.user_revision_entity rev
        ON rev.id = dpr_aud.rev
    WHERE dpr.business_context = 'RENT'
),
house_price AS (
    SELECT
        id_house,
        rent,
        rev,
        ts_price_started AS ts_revision
    FROM datalake_ebdb_smart_price.rental_price_history
    WHERE is_last_status_of_day
),
exclusivity AS (
    SELECT
        hsc.id_house,
        aud.rev,
        IF(aud.special_condition_status = 'OptedIn', TRUE, FALSE) AS is_exclusive,
        ts_revision
    FROM datalake_ebdb_clean.house_special_condition hsc
    INNER JOIN datalake_ebdb_clean.special_condition_aud aud
        ON hsc.id_special_condition = aud.id_special_condition
        AND aud.special_condition_type = 'Exclusivity'
    INNER JOIN datalake_ebdb_user.user_revision_entity r
        ON r.id = aud.rev
    WHERE special_condition_status IN ('OptedIn', 'OptedOut')
),
revision AS (
    SELECT
        m.id_house,
        m.sk_house_listing,
        m.sk_owner,
        m.min_ts_created,
        predicted_price.p_90,
        MAX_BY(entry_condition.key_location, entry_condition.rev) FILTER (
            WHERE entry_condition.ts_revision < m.min_ts_created
        ) AS ef_rev_before,
        MIN_BY(entry_condition.ts_revision, entry_condition.rev) FILTER (
            WHERE entry_condition.ts_revision BETWEEN m.min_ts_created AND DATEADD(DAY, 21, m.min_ts_created)
            AND entry_condition.key_location IN ('KeysWithAgent', 'LockBox', 'FrontDoor', 'Password', 'KeysLocker')
        ) AS ef_rev_after,
        MAX_BY(house_price.rent, house_price.rev) FILTER (
            WHERE house_price.ts_revision < m.min_ts_created
        ) AS pc_rev_before,
        MIN_BY(house_price.ts_revision, house_price.rev) FILTER (
            WHERE house_price.ts_revision BETWEEN m.min_ts_created AND DATEADD(DAY, 21, m.min_ts_created)
            AND house_price.rent <= predicted_price.p_90
        ) AS pc_rev_after,
        MAX_BY(exclusivity.is_exclusive, exclusivity.rev) FILTER (
            WHERE exclusivity.ts_revision < m.min_ts_created
        ) AS ex_rev_before,
        MIN_BY(exclusivity.ts_revision, exclusivity.rev) FILTER (
            WHERE exclusivity.ts_revision BETWEEN m.min_ts_created AND DATEADD(DAY, 21, m.min_ts_created)
            AND exclusivity.is_exclusive
        ) AS ex_rev_after
    FROM messages m
    LEFT JOIN entry_condition
        ON entry_condition.id_house = m.id_house
    LEFT JOIN predicted_price
        ON m.id_house = predicted_price.id_house
        AND m.min_ts_created BETWEEN ts_start AND ts_end
    LEFT JOIN house_price
        ON house_price.id_house = m.id_house
    LEFT JOIN exclusivity
        ON exclusivity.id_house = m.id_house
    GROUP BY 1, 2, 3, 4, 5
),
base AS (
    SELECT
        asp.sk_user AS sk_consultant,
        asp.nome AS consultant_name,
        asp.email AS consultant_email,
        r.sk_house_listing,
        r.sk_owner,
        r.min_ts_created,
        hlco.ts_enrollment_started,
        COALESCE(r.ef_rev_before, 'None') IN ('OwnerPresent', 'None') AS non_facilitated_before,
        CAST(r.ef_rev_after AS DATE) AS ts_facilitated_entry_condition,
        COALESCE(r.pc_rev_before <= p_90, FALSE) AS preco_certo_before,
        CAST(r.pc_rev_after AS DATE) AS ts_preco_certo,
        COALESCE(NOT r.ex_rev_before, TRUE) AS not_exclusive_before,
        CAST(r.ex_rev_after AS DATE) AS ts_exclusive
    FROM revision r
    LEFT JOIN datalake_big_agent.house_rent_listing_consultant AS hlco
        ON hlco.id_house_listing = r.sk_house_listing
        AND hlco.ts_consultant_deleted IS NULL
        AND hlco.consultant_type IN ('ASP')
        AND r.min_ts_created > DATEADD(DAY, -1, TO_DATE(hlco.ts_enrollment_started, 'yyyy-MM-dd HH:mm:ss'))
        AND (TO_DATE(hlco.ts_enrollment_ended, 'yyyy-MM-dd HH:mm:ss') IS NULL OR r.min_ts_created < TO_DATE(hlco.ts_enrollment_ended, 'yyyy-MM-dd HH:mm:ss'))
    LEFT JOIN alocacao_imoveis_ciq_atuacao_asp AS asp_in_ciq_full
        ON hlco.id_user IS NULL
        AND asp_in_ciq_full.sk_house_listing = r.sk_house_listing
        AND asp_in_ciq_full.sk_user_consultant IS NOT NULL
    INNER JOIN dw_public.dim_user asp
        ON asp.sk_user = CAST(hlco.id_user AS BIGINT)
        OR asp.sk_user = asp_in_ciq_full.sk_user_consultant
)
SELECT
    DISTINCT
    sk_consultant,
    sk_house_listing / 1000 AS sk_house,
    sk_house_listing,
    consultant_name,
    team,
    IF(not_exclusive_before = TRUE, ts_exclusive, NULL) AS ts_exclusive,
    IF(preco_certo_before = FALSE, ts_preco_certo, NULL) AS ts_preco_certo,
    IF(non_facilitated_before = TRUE, ts_facilitated_entry_condition, NULL) AS ts_facilitated_entry_condition
FROM base
INNER JOIN datalake_gsheets_clean.asp_consultants_allocation AS aux_asp
    ON aux_asp.id_user = base.sk_consultant
    AND DATE_TRUNC('MM', CURRENT_DATE()) BETWEEN DATE_TRUNC('month', aux_asp.dt_start) AND aux_asp.dt_end
WHERE (
    ts_exclusive BETWEEN DATEADD(DAY, -30, DATE_TRUNC('MM', CURRENT_DATE())) AND DATEADD(MONTH, 1, DATE_TRUNC('MM', CURRENT_DATE()))
    AND not_exclusive_before = TRUE
) OR (
    ts_preco_certo BETWEEN DATEADD(DAY, -30, DATE_TRUNC('MM', CURRENT_DATE())) AND DATEADD(MONTH, 1, DATE_TRUNC('MM', CURRENT_DATE()))
    AND preco_certo_before = FALSE
) OR (
    ts_facilitated_entry_condition BETWEEN DATEADD(DAY, -30, DATE_TRUNC('MM', CURRENT_DATE())) AND DATEADD(MONTH, 1, DATE_TRUNC('MM', CURRENT_DATE()))
    AND non_facilitated_before = TRUE
)
