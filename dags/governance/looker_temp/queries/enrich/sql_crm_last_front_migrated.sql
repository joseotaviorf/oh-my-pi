SELECT
  sk_proposal,
  MAX(f.sk_task) AS last_task
FROM dw_crm.fact_closing_tasks AS f
INNER JOIN dw_crm.dim_closing_task AS d
  ON d.sk_task = f.sk_task
WHERE
  f.sk_proposal > 0 AND d.type IN ('AlinhamentoComPP', 'FrontEnd', 'VerificacaoComIQ')
GROUP BY
  1