WITH proposal_metrics AS (
  SELECT
    id_proposal,
    MIN(
      CASE
        WHEN result IN ('PRE_APPROVED', 'REGULAR') THEN ts_updated
      END
    ) AS ts_first_credit_evaluation_positive,
    MAX(
      CASE
        WHEN result IN ('PRE_APPROVED', 'REGULAR') THEN ts_updated
      END
    ) AS ts_last_credit_evaluation_positive,
    COUNT(DISTINCT id) AS number_evaluations
  FROM
    datalake_docx_clean.credit_evaluation
  WHERE
    status = 'FINISHED'
  GROUP BY
    1
),
proposal_result AS (
  SELECT
    id_proposal,
    id,
    result,
    ROW_NUMBER() OVER (
      PARTITION BY id_proposal
      ORDER BY
        ts_updated DESC,
        ts_created DESC
    ) AS latest_proposal_credit_evaluation_rn
  FROM
    datalake_docx_clean.credit_evaluation
  WHERE
    status = 'FINISHED'
),
group_metrics AS (
  SELECT
    id_group,
    MIN(
      CASE
        WHEN result IN ('PRE_APPROVED', 'REGULAR') THEN ts_updated
      END
    ) AS ts_group_first_credit_evaluation_positive,
    MAX(
      CASE
        WHEN result IN ('PRE_APPROVED', 'REGULAR') THEN ts_updated
      END
    ) AS ts_group_last_credit_evaluation_positive,
    COUNT(DISTINCT id) AS group_number_evaluations
  FROM
    datalake_docx_clean.credit_evaluation
  WHERE
    status = 'FINISHED'
  GROUP BY
    1
),
group_result AS (
  SELECT
    id_group,
    id,
    result,
    ROW_NUMBER() OVER (
      PARTITION BY id_group
      ORDER BY
        ts_updated DESC,
        ts_created DESC
    ) AS latest_group_credit_evaluation_rn
  FROM
    datalake_docx_clean.credit_evaluation
  WHERE
    status = 'FINISHED'
)
SELECT
  ce.id,
  ce.id_proposal,
  ce.id_house,
  ce.id_user,
  ce.id_city,
  ce.id_group,
  ce.scope,
  ce.limit_value,
  ce.proponent_group_type,
  ce.reason,
  ce.result,
  ce.status,
  pr.result AS proposal_last_result,
  gr.result AS group_last_result,
  pm.number_evaluations AS proposal_number_evaluations,
  gm.group_number_evaluations AS group_number_evaluations,
  ce.ts_created,
  ce.ts_updated,
  ce.ts_expires,
  pm.ts_first_credit_evaluation_positive AS ts_proposal_first_credit_evaluation_positive,
  pm.ts_last_credit_evaluation_positive AS ts_proposal_last_credit_evaluation_positive,
  gm.ts_group_first_credit_evaluation_positive,
  gm.ts_group_last_credit_evaluation_positive
FROM
  datalake_docx_clean.credit_evaluation ce
  LEFT JOIN proposal_metrics pm ON pm.id_proposal = ce.id_proposal
  LEFT JOIN proposal_result pr ON pr.id_proposal = ce.id_proposal
  AND pr.latest_proposal_credit_evaluation_rn = 1
  LEFT JOIN group_metrics gm ON gm.id_group = ce.id_group
  LEFT JOIN group_result gr ON gr.id_group = ce.id_group
  AND gr.latest_group_credit_evaluation_rn = 1
