WITH normalize_answers AS (
  SELECT 
    id_candidate,
    UPPER(answer) AS answer,
    CASE
      WHEN UPPER(answer) LIKE 'FACEBOOK%' THEN 'Facebook'
      WHEN UPPER(answer) LIKE 'LINKEDIN%' THEN 'LinkedIn'
      WHEN UPPER(answer) IN ('GLASSDOOR', 'LOVE MONDAYS OU GLASSDOOR', 'LOVEMONDAYS') THEN 'Love Mondays'
      WHEN UPPER(answer) IN ('NEWS IN THE MEDIA', 'NOTICIAS NA MÍDIA', 'NOTÍCIA NA MÍDIA', 'NOTÍCIAS DE MÍDIA', 'NOTÍCIAS NA MÍDIA') THEN 'Notícias na Mídia'
      WHEN UPPER(answer) LIKE 'PÁGINA DE CARREIRAS%' OR UPPER(answer) = 'CAREERS PAGE OF QUINTOANDAR' OR UPPER(answer) = 'SITE DE CARREIRAS DO QUINTOANDAR' THEN 'Página de Carreiras'
      WHEN UPPER(answer) LIKE '%EMAIL%' OR UPPER(answer) LIKE '%E-MAIL%' THEN 'Email'
      WHEN UPPER(answer) IN ('SEARCH SITE', 'SITE DE BUSCA', 'SITE DE BUSCAS', 'BUSCA NO SITE') THEN 'Site de Busca'
      WHEN UPPER(answer) LIKE 'UNIVERSIDADE%' OR UPPER(answer) IN ('UNIVERSITY', 'DIVULGAÇÃO EM MEU CURSO / ESCOLA') THEN 'Universidade/Curso'
      WHEN UPPER(answer) IN ('RECOMENDAÇÃO DE AMIGO(A)', 'RECOMENDAÇÃO DE AMIGOS', 'RECOMENDAÇÃO DE UM AMIGO', 'RECOMENDAÇÃO DE UM AMIGO(A)', 'RECOMMENDATION OF FRIENDS', 'INDICAÇÃO DE AMIGOS', 'INDICAÇÃO DE AMIGOS / COLEGAS / OUTROS CORRETORES DO QUINTOANDAR') THEN 'Recomendação de Amigo(a)'
      WHEN UPPER(answer) LIKE '%HUNTING%' THEN 'Hunting'
      WHEN UPPER(answer) IN ('OTHER', 'OUTRO', 'OUTROS') THEN 'Outros'
      ELSE initcap(answer)
    END answer_normalized
  FROM 
    datalake_workable_redshift_clean.answers
  WHERE
    question LIKE '%Por onde você ficou sabendo dessa oportunidade?%'
)
SELECT 
  id_candidate,
  DENSE_RANK() OVER (ORDER BY answer_normalized) AS sk_info_source,
  answer,
  answer_normalized
FROM 
  normalize_answers