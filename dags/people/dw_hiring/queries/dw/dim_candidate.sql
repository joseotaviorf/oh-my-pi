WITH opportunity_info_source AS (
  SELECT
    id_candidate,
    answer
  FROM
    datalake_workable_redshift_clean.answers
  WHERE
    question LIKE '%Por onde você ficou sabendo dessa oportunidade?%'
)
SELECT
  MD5(CAST(c.id AS BINARY)) AS sk_candidate,
  COALESCE(c.headline, '-1') AS headline,
  COALESCE(c.email, '-1') AS email,
  COALESCE(
    ecf_requisitions.candidate_source,
    CASE
      WHEN ecf_candidate.is_hunted
      OR (
        c.source = 'Uploaded'
        AND c.application_method = 'Uploaded'
      ) THEN 'Hunting'
      WHEN c.source = 'referral'
      OR c.application_method = 'Referred'
      OR c.source_category = 'Referrals' THEN 'Referência'
      WHEN c.source = 'internal_application' THEN 'Aplicação interna'
      WHEN c.application_method = 'Applied'
      OR (
        c.source_category = 'Job Boards'
        AND c.application_method = 'LinkedIn'
      ) THEN 'Orgânico'
      WHEN c.source = 'Copied'
      AND c.application_method = 'Copied' THEN 'Copied'
      WHEN c.source IS NULL
      AND c.application_method = 'Uploaded'
      AND c.source_category = 'Other' THEN 'Suggested by Workable'
    END,
    '-1'
  ) AS source_candidate,
  COALESCE(ois.answer, '-1') AS opportunity_info_source,
  NOW() AS ts_load
FROM
  datalake_workable_redshift_clean.candidates AS c
LEFT JOIN 
  datalake_workable.custom_fields AS ecf_candidates 
    ON c.id = ecf_candidates.id_resource
LEFT JOIN 
  opportunity_info_source AS ois 
    ON c.id = ois.id_candidate
LEFT JOIN 
  datalake_workable_redshift_clean.requisitions AS r 
    ON c.id = r.id_candidate
LEFT JOIN 
  datalake_workable.custom_fields AS ecf_requisitions 
    ON r.id = ecf_requisitions.id_resource
LEFT JOIN 
  datalake_workable.custom_fields AS ecf_candidate 
    ON c.id = ecf_candidate.id_resource