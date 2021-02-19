WITH
imovel_quintoandar_consultant AS (
SELECT
    DISTINCT
	ia.id,
	ia.usuarioquecadastrou_id
FROM
    datalake_ebdb_raw_prod.Imovel_AUD ia
JOIN
    datalake_ebdb_raw_prod.Imovel i
      ON i.id = ia.id
      AND i.id NOT IN (893189969,893189245,893188683,893183943)
WHERE i.datacriacao >= '2020-10-24'
  AND ia.usuarioquecadastrou_mod = True
),
base AS (
SELECT
    dhl.sk_house_listing,
    dhl.id_house,
    coalesce(nullif(dhl.sk_autonomous_agent,-1),i_quintoandar_consultant.usuarioquecadastrou_id) as sk_quintoandar_consultant,
    CASE WHEN dhl.is_autonomous_agent = TRUE OR aa.vinculado = 'Sim' OR (i_quintoandar_consultant.id is not null AND dpa.id_user is not null) THEN TRUE
         ELSE FALSE END AS is_quintoandar_consultant,
    CASE WHEN aa.vinculado = 'Sim' OR (i_quintoandar_consultant.id is not null AND dpa.id_user is not null) THEN TRUE
         ELSE FALSE END AS is_am
FROM
    dim_house_listing dhl
LEFT JOIN
    imovel_quintoandar_consultant i_quintoandar_consultant
      ON dhl.id_house = i_quintoandar_consultant.id
LEFT JOIN
    dim_partner_agent dpa
      ON dpa.id_user = i_quintoandar_consultant.usuarioquecadastrou_id
LEFT JOIN
    datalake_raw.gsheets_house_autonomous_agent aa
      ON dhl.id_house = aa.id_house
)
SELECT
  DISTINCT
    sk_house_listing,
    id_house,
    sk_quintoandar_consultant,
    is_quintoandar_consultant,
    is_am AS is_account_management
FROM
   base
WHERE is_quintoandar_consultant
   OR is_am
