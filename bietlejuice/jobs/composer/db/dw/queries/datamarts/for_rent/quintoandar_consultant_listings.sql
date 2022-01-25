WITH check_ciq_full AS (
    SELECT
        JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId') AS id_house_external
    FROM
        datalake_big_agent_prod.House
    INNER JOIN
        datalake_big_agent_prod.Agency
            ON Agency.id_house = house.id
    GROUP BY
        JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId')
    HAVING
        COUNT(JSON_EXTRACT_PATH_TEXT( House.details, 'houseExternalId'))  > 1
),
last_enrollment AS (
    SELECT
        id_house,
        MAX(id_enrollment) AS id_enrollment
    FROM
        datalake_big_agent_prod.Agency
    GROUP BY 1
),

quintoandar_consultant_listings_rent as
(
    SELECT
        dhl.sk_house_listing,
        CAST(JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId') AS BIGINT) AS id_house,
        CAST(JSON_EXTRACT_PATH_TEXT(Agent.details, 'userExternalId') AS BIGINT) AS sk_quintoandar_consultant,
        lf.mkt_origin = 'CIQ' AS mkt_origin_ciq,
        lf.mkt_origin = 'CIQ' AND  program.name='CIQ_FULL' AS is_ciq_origin,
        CASE
            WHEN lf.mkt_origin = 'CIQ'  THEN TRUE
            ELSE program.name='CIQ_MANAGER'
        END AS is_account_manager,
        CASE
            WHEN ccf.id_house_external IS NOT NULL THEN 'CIQ_FULL'
            ELSE program.name
        END AS type_big_agent,
        lbc.business_context AS businesscontext,
        NULL as businesscontext_detail,
        Agency.dt_since AS dt_ciq_started,
        dp.id_partner
    FROM
        datalake_big_agent_prod.House
    LEFT JOIN
        last_enrollment le
            ON le.id_house=House.id
    LEFT JOIN
        datalake_big_agent_prod.Agency
            ON Agency.id_house=le.id_house
            AND Agency.id_enrollment=le.id_enrollment
    LEFT JOIN 
        datalake_big_agent_prod.enrollment
            ON enrollment.id=le.id_enrollment
    LEFT JOIN
        datalake_big_agent_prod.Agent
            ON agent.id=enrollment.id_agent
    LEFT JOIN
        datalake_big_agent_prod.program
            ON program.id=enrollment.id_program
    LEFT JOIN
        dim_house_listing dhl
            ON dhl.id_house=JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId')
    LEFT JOIN
        fact_house_listing_flows lf
            ON dhl.id_house = lf.sk_house_listing/1000
    LEFT JOIN
        check_ciq_full ccf
            ON ccf.id_house_external=JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId')
    LEFT JOIN 
        dim_partner_agent dpa
            on dpa.id_user=CAST(JSON_EXTRACT_PATH_TEXT(Agent.details, 'userExternalId') AS BIGINT)
    LEFT JOIN 
        dim_partner dp
            on dp.id_partner=dpa.id_partner
    INNER JOIN
        datalake_ebdb_clean_prod.listing_business_context lbc
            ON lbc.id_house=JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId')
            AND lbc.business_context='RENT'
    ),
quintoandar_consultant_listings_sale AS
(
    SELECT distinct
    dl.sk_sale_listing AS sk_house_listing,
    i.id AS id_house,
    pa.id_user AS sk_quintoandar_consultant,
    lf.mkt_origin = 'CIQ' AS mkt_origin_ciq,
    lf.mkt_origin = 'CIQ' AS is_ciq_origin,
    CASE WHEN lf.mkt_origin = 'CIQ'  THEN TRUE ELSE false END AS is_account_manager,
    'CIQ_FULL'AS type_big_agent,
    'SALE' AS businesscontext,
    dp.id_partner
FROM
    datalake_ebdb_clean_prod.house i
LEFT JOIN
    datalake_ebdb_raw_prod.listingbusinesscontext lbc
        ON i.id=lbc.imovelid
INNER JOIN
    dim_partner_agent pa
        ON pa.id_user=i.id_user_registrant
LEFT JOIN
    dim_partner dp
        ON dp.id_partner=pa.id_partner
LEFT JOIN
    sale.dim_listing dl
        ON dl.sk_house=i.id
LEFT JOIN
    sale.fact_listing_flows lf
        ON LEFT(lf.sk_house_listing,9)=i.id


WHERE
    businesscontext='SALE'
    AND dp.type='AUTONOMOUS_AGENT'
    AND (lf.sk_lead_date>=20210601 or lf.sk_first_listing_date>=20210601)

ORDER BY 2,1
),

base_forrent AS (

SELECT distinct
    dhl.id_house,
    dhl.short_id_house,
    dhl.house_neighborhood,
    dhl.house_address,
    dhl.house_number,
    dhl.house_zipcode,
    dhl.house_city,
    REGEXP_REPLACE(dhl.house_complement,'([^0-9])','') as complement,
    fhl.sk_owner,
    du.nome,
    du.email,
    du.telefone_principal

FROM
    dim_house_listing dhl
LEFT JOIN
    fact_house_listings fhl
        ON LEFT(fhl.sk_house_listing,9)=dhl.id_house
LEFT JOIN
    dim_user du
        ON du.id=fhl.sk_owner
LEFT JOIN
    dim_region dr
        ON dr.sk_region=fhl.sk_region
WHERE
    city_group in ('RMSP','Rio de Janeiro')
    AND dhl.status='publicado'
    AND is_for_sale=FALSE
    AND is_for_rent=TRUE
ORDER BY 1,2),

first_rev AS (

SELECT
    ia.id_house,
    MIN(rev) AS first_rev
FROM
    datalake_ebdb_clean_prod.house_aud ia
INNER JOIN
    quintoandar_consultant_listings_sale qcls
        ON ia.id_house=qcls.id_house
GROUP BY 1),

dados_cadastro AS (
SELECT
    ia.id_house,
    mod_is_for_rent,
    mod_is_for_sale,
    is_for_rent,
    is_for_sale
FROM
    datalake_ebdb_clean_prod.house_aud ia
INNER JOIN
    first_rev fr
        ON fr.id_house=ia.id_house
        AND ia.rev=fr.first_rev
),

last_change_user AS (

SELECT
    CAST(JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId') AS BIGINT) AS id_house,
    Agency.dt_since AS dt_ciq_started
FROM
    datalake_big_agent_prod.House
LEFT JOIN
    last_enrollment le
        ON le.id_house=House.id
LEFT JOIN
    datalake_big_agent_prod.Agency
        ON Agency.id_house=le.id_house
        AND Agency.id_enrollment=le.id_enrollment

),

last_change_sale AS (
SELECT
    ia.id_house,
    MAX(FROM_UNIXTIME(u.ts_revision/ 1000)) as ts_sale
 FROM
    datalake_ebdb_clean_prod.house_aud ia
LEFT JOIN 
    datalake_ebdb_clean_prod.user_revision_entity u
        ON u.id=ia.rev
WHERE 
    mod_is_for_sale=TRUE  
    AND is_for_sale=TRUE
GROUP BY  1
),
quintoandar_consultant_listings AS (
(
SELECT
   dl.sk_sale_listing  AS sk_house_listing,
    qcls.id_house,
    qcls.sk_quintoandar_consultant,
    lf.mkt_origin = 'CIQ' AS mkt_origin_ciq,
    lf.mkt_origin = 'CIQ' AS is_ciq_origin,
    CASE WHEN lf.mkt_origin = 'CIQ'  THEN TRUE ELSE FALSE  END AS is_account_manager,
    'CIQ_FULL'AS type_big_agent,
    'SALE' AS businesscontext,
    CASE
        WHEN dc.is_for_rent IS TRUE AND dc.is_for_sale IS TRUE THEN 'cadastrado como rent e sale'
        WHEN dc.is_for_rent IS TRUE AND (lcs.ts_sale>=lcu.dt_ciq_started OR qclr.type_big_agent='CIQ_FULL') THEN 'cadastrado como rent e virou sale'
        WHEN dc.is_for_sale IS TRUE AND bf.id_house IS NOT NULL AND qcls.id_house<>bf.id_house AND dc.is_for_rent IS FALSE  THEN 'Cadastro de novo Id imovel para ForSale de imovel que já existe em ForRent'
        WHEN dc.is_for_rent IS FALSE AND dc.is_for_sale IS TRUE THEN 'cadastrado somente como sale'
        ELSE 'check'
    END AS businesscontext_detail,
    null as dt_ciq_started,
    qcls.id_partner
FROM
    quintoandar_consultant_listings_sale qcls
LEFT JOIN
    dados_cadastro dc
        ON dc.id_house=qcls.id_house
LEFT JOIN
    datalake_ebdb_clean_prod.house i
        ON i.id=qcls.id_house
LEFT JOIN
    dim_user du
        ON i.id_user=du.id
LEFT JOIN
    base_forrent bf
        ON i.address=bf.house_address
        AND i.number=bf.house_number
        AND du.email=bf.email
        and REGEXP_REPLACE(i.complement,'([^0-9])','')=bf.complement
        AND du.email<>'lisboagabrielysantos@gmail.com'
LEFT JOIN sale.dim_listing dl
        ON dl.sk_house=qcls.id_house
LEFT JOIN
    sale.fact_listing_flows lf
        ON LEFT(lf.sk_house_listing,9)=qcls.id_house
LEFT JOIN
    last_change_user lcu
        ON lcu.id_house=qcls.id_house
LEFT JOIN
    last_change_sale lcs
        ON lcs.id_house=qcls.id_house
LEFT JOIN
    quintoandar_consultant_listings_rent qclr
        ON qclr.id_house=qcls.id_house
WHERE
   lcs.ts_sale>=lcu.dt_ciq_started
   OR dc.is_for_sale IS TRUE
   OR qclr.type_big_agent='CIQ_FULL'
)
UNION

(
SELECT
    *
FROM
    quintoandar_consultant_listings_rent
)
)

SELECT
    *
FROM
    quintoandar_consultant_listings
ORDER BY
    id_house