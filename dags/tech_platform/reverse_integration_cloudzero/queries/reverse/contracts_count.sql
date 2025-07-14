SELECT
  count(distinct dc.sk_contract) AS contracts_count
FROM dw_rent.dim_contract dc
WHERE dc.status in ('Ativo', 'Finalizado')
  AND dc.type <> 'DealOnly'
  AND date(coalesce(dc.dt_start, dc.dt_entrance)) <= current_date
  AND (dc.dt_annulment IS NULL OR date(dc.dt_annulment) >= current_date)
