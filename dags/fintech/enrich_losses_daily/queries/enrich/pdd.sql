WITH analytical_base AS (
  SELECT 
    m.id_invoice,
    m.id_contract,
    case when date(f.dt_termination) is not null and date(f.dt_termination) <= m.dt_closing then 'Finalizado' else 'Ativo' end as status,
    abs(m.due_amount) as due_amount,
    m.frequency,
    m.guarantee_type,
    m.pd_range_rule_e,
    abs(m.provision_balance_p4_delay_e) as provision_balance_p4_delay_e,   
    m.user,
    m.dt_closing,
    m.origin_factor
  FROM 
    datalake_losses_daily.provision AS m
  LEFT JOIN 
    (SELECT DISTINCT * FROM datalake_ebdb_contract.contract) AS f on f.id = m.id_contract
)
SELECT 
  pd_range_rule_e, 
  status, 
  COUNT(DISTINCT id_contract) AS contracts, 
  sum(due_amount) AS wallet, 
  sum(provision_balance_p4_delay_e) AS pdd, 
  dt_closing
FROM 
  analytical_base 
GROUP BY 1,2,6