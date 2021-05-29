WITH
imovel_quintoandar_consultant AS (
SELECT
	ia.id,
	ia.usuarioquecadastrou_id,
	max(ia.rev) as max_rev_uid
FROM
    datalake_ebdb_raw_prod.Imovel_AUD ia
JOIN
    datalake_ebdb_raw_prod.Imovel i
      ON i.id = ia.id
      AND i.id NOT IN (893189969,893189245,893188683,893183943)
WHERE i.datacriacao >= '2020-10-24'
  AND ia.usuarioquecadastrou_mod = True
GROUP BY 1, 2
),
base AS (
SELECT
    dhl.sk_house_listing,
    dhl.id_house,
    lf.mkt_origin = 'CIQ' AS is_mkt_origin_ciq,
    dhl.is_autonomous_agent as is_autonomous_agent_ciq_origin,
    aa.vinculado as gsheets_accmgmt_vinculado,
    (i_quintoandar_consultant.id is not null AND dpa.id_user is not null) as usuarioquecadastrou_mod_and_partner_agent,
    dpa.id_user,
    i_quintoandar_consultant.max_rev_uid,
    coalesce(nullif(dhl.sk_autonomous_agent,-1),i_quintoandar_consultant.usuarioquecadastrou_id) as sk_quintoandar_consultant
FROM dim_house_listing dhl
LEFT JOIN fact_house_listing_flows lf
    ON dhl.id_house = lf.sk_house_listing/1000
LEFT JOIN
    imovel_quintoandar_consultant i_quintoandar_consultant
      ON dhl.id_house = i_quintoandar_consultant.id
LEFT JOIN
    dim_partner_agent dpa
      ON dpa.id_user = i_quintoandar_consultant.usuarioquecadastrou_id
LEFT JOIN
    datalake_raw.gsheets_house_autonomous_agent aa
      ON dhl.id_house = aa.id_house
),
base2 as (
SELECT
    sk_house_listing,
    id_house,
    sk_quintoandar_consultant,
    is_mkt_origin_ciq AS is_ciq_origin,
    CASE WHEN gsheets_accmgmt_vinculado = 'Sim' OR usuarioquecadastrou_mod_and_partner_agent THEN TRUE ELSE FALSE END AS is_account_manager,
    max(max_rev_uid) as max_rev_uid
FROM
   base
GROUP BY 1, 2, 3, 4, 5
),
final_flags AS (
SELECT
    sk_house_listing,
    id_house,
    sk_quintoandar_consultant,
    is_ciq_origin as mkt_origin_ciq,
    is_ciq_origin AND is_account_manager = FALSE as is_ciq_origin,
    (is_ciq_origin AND is_account_manager = TRUE) OR (is_ciq_origin = FALSE AND is_account_manager = TRUE) as is_account_management,
    max_rev_uid
FROM
    base2
WHERE mkt_origin_ciq OR is_account_manager
),
final_flags2 as (
SELECT
    sk_house_listing,
    id_house,
    max_rev_uid,
    DENSE_RANK() over(partition by id_house order by max_rev_uid desc) as max_rev_uid_order,
    sk_quintoandar_consultant,
    mkt_origin_ciq,
    is_ciq_origin,
    CASE WHEN mkt_origin_ciq THEN TRUE ELSE is_account_management END as is_account_manager,
    CASE
        WHEN is_ciq_origin THEN 'CIQ_FULL'
        WHEN is_account_management THEN 'CIQ_MANAGER' END AS type_big_agent
FROM
    final_flags
)
SELECT
    sk_house_listing,
    id_house,
    sk_quintoandar_consultant,
    mkt_origin_ciq,
    is_ciq_origin,
    is_account_manager,
    type_big_agent
FROM
    final_flags2
WHERE (max_rev_uid_order = 1 OR max_rev_uid_order IS NULL)
