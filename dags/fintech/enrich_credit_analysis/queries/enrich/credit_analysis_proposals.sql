WITH credit_analysis_ordered AS (
  SELECT
    id_proposal,
    id_credit_analysis,
    id_variant,
    category,
    bypass,
    ts_updated
  FROM
    datalake_sorting_hat_clean.credit_analysis
  ORDER BY
    id_proposal, ts_updated
),

credit_analysis_proposals AS (
  SELECT
    id_proposal,
    FIRST(id_credit_analysis) AS id_first_credit_analysis,
    LAST(id_credit_analysis) AS id_last_credit_analysis,
    FIRST(id_variant) AS id_first_variant,
    LAST(id_variant, true) AS id_last_variant_not_null,
    FIRST(category) AS first_category,
    LAST(category) AS last_category,
    LAST(category, true) AS last_category_not_null,
    MAX(bypass) AS max_bypass
  FROM
    credit_analysis_ordered
  WHERE
    id_proposal IS NOT NULL
  GROUP BY 1
),

credit_evaluations_prev AS (
  SELECT
    id_proposal,
    proposal_last_result,
    proposal_number_evaluations,
    ts_proposal_first_credit_evaluation_positive,
    ts_proposal_last_credit_evaluation_positive,
    ROW_NUMBER() OVER(PARTITION BY id_proposal ORDER BY ts_updated DESC, ts_created DESC) AS rn
  FROM
    datalake_docx.credit_evaluation
),

credit_evaluations AS (
  SELECT
    id_proposal,
    proposal_last_result,
    proposal_number_evaluations,
    ts_proposal_first_credit_evaluation_positive,
    ts_proposal_last_credit_evaluation_positive
  FROM
    credit_evaluations_prev
  WHERE
    rn = 1
), 
cpf_retenant AS (
  SELECT 
    cp.cpf,
    MIN(c.dt_started) AS min_dt_started
  FROM 
    datalake_ebdb_clean.contract_person AS cp
  JOIN 
    datalake_ebdb_clean.contract AS c
      ON cp.id_contract = c.id
  WHERE 
    c.status IN ('Ativo','Finalizado') 
    AND cp.type IN ('Inquilino')
    AND cpf NOT IN ('','0', '99999999999')
  GROUP BY 1

),

dti AS (
  SELECT
    p.id AS id_proposal,
    NULLIF(SUM(p2.monthly_income),0) AS income,
    MAX(p.rent_value + COALESCE(p.condo_value,0) + COALESCE(p.iptu_value,0) + COALESCE(p.home_insurance_value,0)) AS package,
    CASE 
      WHEN SUM(p2.monthly_income) != 0 THEN CAST(MAX(p.rent_value + COALESCE(p.condo_value,0) + COALESCE(p.iptu_value,0) + COALESCE(p.home_insurance_value,0))/SUM(p2.monthly_income) AS DECIMAL(9,2))
      ELSE NULL 
    END AS dti,
    MAX(IF(crt.cpf IS NOT NULL,TRUE,FALSE)) AS is_retenant,
    COUNT(DISTINCT CASE WHEN is_going_to_reside = TRUE THEN p2.id END) as nbr_residents,
    COUNT(DISTINCT CASE WHEN is_going_to_reside = FALSE THEN p2.id END) as nbr_supportive_users
  FROM
    datalake_sorting_hat_clean.proposal p 
  LEFT JOIN 
    datalake_sorting_hat_clean.proponent p2 
      ON p.id = p2.id_proposal 
  LEFT JOIN 
    cpf_retenant crt
      ON p2.cpf = crt.cpf 
      AND crt.min_dt_started < p.ts_created
  GROUP BY 1
),

sorting_hat_proposals_prev AS (
  SELECT
    p.id,
    p.status,
    p.ts_analyzed,
    p.ts_processed,
    pv.ts_analyzed AS ts_analyzed_version,
    ROW_NUMBER() OVER (PARTITION by p.id ORDER BY pv.ts_analyzed) AS rn
  FROM
    datalake_sorting_hat_clean.proposal AS p
  LEFT JOIN
    datalake_sorting_hat_clean.proposal_version AS pv
      ON p.id = pv.id_proposal
),

sorting_hat_proposals AS (
  SELECT
    id AS id_proposal,
    status,
    ts_analyzed,
    ts_processed,
    COALESCE(ts_analyzed_version, ts_analyzed) AS ts_first_analyzed
  FROM
    sorting_hat_proposals_prev
  WHERE
    rn = 1
) ,  
screening_result AS (
SELECT 
    CASE  
      WHEN r.city_name ='São Paulo' THEN 'G01' 
      WHEN r.city_name ='Rio de Janeiro' THEN 'G02'
      WHEN r.city_name in (
                         'Mauá', 
                         'São José dos Pinhais',
                         'São José',
                         'São Leopoldo',
                         'Ribeirão Preto',
                         'Mogi das Cruzes',
                         'Diadema',
                         'Novo Hamburgo',
                         'Taboão da Serra',
                         'Canoas',
                         'Curitiba',
                         'Osasco',
                         'Sorocaba',
                         'Guarulhos',
                         'São José dos Campos',
                         'Cotia',
                         'Porto Alegre',
                         'Campinas') THEN 'G03'
      WHEN r.city_name IN (
                         'Santo André',
                         'Goiânia',
                         'São Bernardo do Campo',
                         'Florianópolis',
                         'Uberlândia',
                         'Santos',
                         'Barueri',
                         'Belo Horizonte',
                         'Jundiaí',
                         'Brasília',
                         'Recife',
                         'Salvador',
                         'Niterói',
                         'São Caetano do Sul') THEN 'G04'
      WHEN r.city_name IN ('Carapicuíba',
                         'Engenho Novo',
                         'Estância Velha',
                         'São Vicente',
                         'Sapucaia do Sul',
                         'Matão',
                         'Santa Luzia',
                         'Votorantim',
                         'Três Rios',
                         'Almirante Tamandaré',
                         'Belém',
                         'Embu das Artes',
                         'Nova Iguaçu',
                         'Amarante',
                         'Palhoça',
                         'Aparecida de Goiânia',
                         'Sabará',
                         'Contagem',
                         'Valinhos',
                         'Manaus',
                         'reFortaleza',
                         'Pinhais',
                         'Várzea Paulista',
                         'São José do Rio Preto',
                         'Vitória',
                         'Nova Lima',
                         'Santana de Parnaíba') THEN 'G05'
      ELSE 'G05'
    END AS regionalizacao,
    CASE 
      WHEN sr.score>=820 THEN 'A4'
      WHEN sr.score>=500 THEN 'C2'
      WHEN sr.score>=320 THEN 'E3'
      WHEN sr.score>=280 THEN 'F3'
      ELSE 'G7' 
    END AS RATING_RU_INTERNAL_TGT_V1,
          
    CASE 
      WHEN sr.score>=963 THEN 'A2'
      WHEN sr.score>=932 THEN 'A3'
      WHEN sr.score>=885 THEN 'A4'
      WHEN sr.score>=818 THEN 'B2'
      WHEN sr.score>=727 THEN 'C1'
      WHEN sr.score>=595 THEN 'D2'
      WHEN sr.score>=538 THEN 'D4'
      WHEN sr.score>=408 THEN 'E3'
      ELSE 'G2' 
    END AS RATING_RU_INTERNAL_TGT_REFIT,
    
    CASE 
      WHEN sr.score>=822 THEN 'A2'
      WHEN sr.score>=693 THEN 'A3'
      WHEN sr.score>=608 THEN 'B1'
      WHEN sr.score>=521 THEN 'B2'
      WHEN sr.score>=441 THEN 'C1'
      WHEN sr.score>=325 THEN 'D1'
      WHEN sr.score>=287 THEN 'E3'
      WHEN sr.score>=262 THEN 'F4'
      ELSE                   'I1' 
    END AS HOMELESS_RU_V1,
                        
    CASE WHEN sr.score>=809 THEN 'A2'
      WHEN sr.score>=699 THEN 'A3'
      WHEN sr.score>=571 THEN 'B1'
      WHEN sr.score>=471 THEN 'B2'
      WHEN sr.score>=374 THEN 'C1'
      WHEN sr.score>=283 THEN 'D1'
      WHEN sr.score>=275 THEN 'E3'
      WHEN sr.score>=251 THEN 'F4'
      ELSE                   'I1' 
    END AS HOMELESS_RU_V2,
    CASE 
      WHEN sr.score>=800 THEN 'A3'
      WHEN sr.score>=441 THEN 'D1'
      WHEN sr.score>=294 THEN 'E3'
      WHEN sr.score>=268 THEN 'F2'
      ELSE                   'G1' 
    END AS RATING_RU_INTERNAL_TGT_REG_G01,
    
    CASE 
      WHEN sr.score>=800 THEN 'A4'
      WHEN sr.score>=441 THEN 'D1'
      WHEN sr.score>=316 THEN 'E2'
      WHEN sr.score>=272 THEN 'F1' 
      ELSE                   'G4' 
    END AS RATING_RU_INTERNAL_TGT_REG_G02,
    CASE 
      WHEN sr.score>=800 THEN 'A4'
      WHEN sr.score>=441 THEN 'D2'
      WHEN sr.score>=306 THEN 'E3'
      WHEN sr.score>=298 THEN 'E3'
      ELSE                   'I1' 
    END AS RATING_RU_INTERNAL_TGT_REG_G03,
         
    CASE 
      WHEN sr.score>=800 THEN 'A4'
      WHEN sr.score>=441 THEN 'D1'
      WHEN sr.score>=361 THEN 'E3'
      WHEN sr.score>=232 THEN 'E4'
      ELSE                   'G7' 
    END AS RATING_RU_INTERNAL_TGT_REG_G04,                      
                                 
    CASE 
      WHEN sr.score>=914 THEN 'B1'
      WHEN sr.score>=816 THEN 'B2'
      WHEN sr.score>=570 THEN 'C1'
      WHEN sr.score>=351 THEN 'D2'
      ELSE                   'E4' 
    END AS RATING_RU_EXTERNAL_TGT_REG_SP,
                          
    CASE 
      WHEN sr.score>=914 THEN 'B1'
      WHEN sr.score>=816 THEN 'B2'
      WHEN sr.score>=570 THEN 'C2'
      WHEN sr.score>=351 THEN 'D2' 
      ELSE                   'E5' 
    END AS RATING_RU_EXTERNAL_TGT_REG_RIO,
    CASE 
      WHEN sr.score>=914 THEN 'B1'
      WHEN sr.score>=816 THEN 'B2'
      WHEN sr.score>=570 THEN 'C2'
      WHEN sr.score>=351 THEN 'D3'
      ELSE                   'F4' 
    END AS RATING_RU_EXTERNAL_TGT_REG_CITIES1,
         
    CASE 
      WHEN sr.score>=914 THEN 'B1'
      WHEN sr.score>=816 THEN 'C1'
      WHEN sr.score>=570 THEN 'D1'
      WHEN sr.score>=351 THEN 'D4'
      ELSE                   'F5' 
    END AS RATING_RU_EXTERNAL_TGT_REG_CITIES2,
         
    CASE 
      WHEN sr.score>=919 THEN 'A3'
      WHEN sr.score>=512 THEN 'C2'
      WHEN sr.score>=210 THEN 'E1'
      WHEN sr.score>=110 THEN 'E5'
      ELSE                   'G4' 
    END AS RATING_RU_REJECTED_INFERENCE, 
    CASE 
      WHEN r.city_name ='São Paulo' THEN 'SP' 
      WHEN r.city_name ='Rio de Janeiro' THEN 'RJ' 
      WHEN r.city_name in ('Belo Horizonte','Porto Alegre','Campinas','Curitiba') THEN 'Cities1' 
      ELSE 'Cities2' 
    END AS regionalizacao_external_tgt,
    sr.*  
FROM 
    datalake_ebdb_clean.proposal AS p
LEFT JOIN
    datalake_ebdb_clean.house AS h 
        ON h.id = p.id_house
LEFT JOIN
    datalake_region.region AS r 
        ON r.id = h.id_region
LEFT JOIN
    datalake_sorting_hat_clean.screening_result AS sr 
        ON sr.id_proposal = p.id
)

SELECT
  shp.id_proposal,
  rg.id_documentation_ebdb AS id_proposal_from_rg,
  cap.id_first_credit_analysis,
  cap.id_last_credit_analysis,
  cap.id_first_variant,
  cap.id_last_variant_not_null,
  dti.income,
  dti.nbr_residents,
  dti.nbr_supportive_users,
  rg.score AS rental_guarantee_category,
  rg.guarantee_type AS paid_guarantee_type,
  rg.guarantee_source,
  ct.guarantee_type,
  ceval.proposal_last_result AS last_result,
  dti.package,
  cr.risk_category,
  shp.status,
  dti.dti,
  cr.risk_category_canon,
  CASE 
      WHEN cap.id_first_variant IN (69,71,72,74,76,77) THEN cr.RATING_RU_INTERNAL_TGT_REFIT
      WHEN cap.id_first_variant IN (49,61,64,67,70) THEN cr.HOMELESS_RU_V1
      WHEN cap.id_first_variant IN (56,58,60,62,63,65,66,68) AND cr.regionalizacao='G01' THEN RATING_RU_INTERNAL_TGT_REG_G01
      WHEN cap.id_first_variant IN (56,58,60,62,63,65,66,68) AND cr.regionalizacao='G02' THEN RATING_RU_INTERNAL_TGT_REG_G02
      WHEN cap.id_first_variant IN (56,58,60,62,63,65,66,68) AND cr.regionalizacao='G03' THEN RATING_RU_INTERNAL_TGT_REG_G03
      WHEN cap.id_first_variant IN (56,58,60,62,63,65,66,68) AND cr.regionalizacao='G04' THEN RATING_RU_INTERNAL_TGT_REG_G04
      WHEN cap.id_first_variant IN (56,58,60,62,63,65,66,68) AND cr.regionalizacao='G05' THEN RATING_RU_INTERNAL_TGT_REG_G03 
      WHEN cap.id_first_variant IN (35,37,39,41,43,44,46,48,50,52,53,55) THEN RATING_RU_INTERNAL_TGT_V1
      WHEN cap.id_first_variant IN (42,45,47,51,54,57,59) THEN RATING_RU_REJECTED_INFERENCE
      WHEN cap.id_first_variant IN (73) THEN HOMELESS_RU_V2
      WHEN cap.id_first_variant IN (1,2,34,36,38,40) AND cr.regionalizacao_external_tgt='SP' THEN RATING_RU_EXTERNAL_TGT_REG_SP
      WHEN cap.id_first_variant IN (1,2,34,36,38,40) AND cr.regionalizacao_external_tgt='RJ' THEN RATING_RU_EXTERNAL_TGT_REG_RIO
      WHEN cap.id_first_variant IN (1,2,34,36,38,40) AND cr.regionalizacao_external_tgt='Cities1' THEN RATING_RU_EXTERNAL_TGT_REG_CITIES1
      WHEN cap.id_first_variant IN (1,2,34,36,38,40) AND cr.regionalizacao_external_tgt='Cities2' THEN RATING_RU_EXTERNAL_TGT_REG_CITIES2
      ELSE 'Avaliar_Modelo' 
  END AS risk_category_canon_past_filler,
  dti.is_retenant,
  cap.first_category,
  cap.last_category,
  cap.last_category_not_null,
  cap.max_bypass,
  cr.score AS internal_score,
  ceval.proposal_number_evaluations AS number_evaluations,
  shp.ts_analyzed,
  shp.ts_first_analyzed,
  ceval.ts_proposal_first_credit_evaluation_positive AS ts_first_credit_evaluation_positive,
  rg.ts_created AS ts_paid_guarantee_created,
  rg.ts_paid AS ts_guarantee_paid,
  ceval.ts_proposal_last_credit_evaluation_positive AS ts_last_credit_evaluation_positive,
  shp.ts_processed
FROM
  sorting_hat_proposals AS shp
LEFT JOIN
  credit_analysis_proposals AS cap
    ON shp.id_proposal = cap.id_proposal
LEFT JOIN
  credit_evaluations AS ceval
    ON shp.id_proposal = ceval.id_proposal
LEFT JOIN
  dti
    ON shp.id_proposal = dti.id_proposal
LEFT JOIN
  screening_result AS cr
    ON shp.id_proposal = cr.id_proposal
LEFT JOIN
  datalake_rental_guarantee.guarantee AS rg
    ON shp.id_proposal = rg.id_documentation_ebdb
LEFT JOIN
  datalake_ebdb_clean.contract AS ct
    ON shp.id_proposal = ct.id_proposal