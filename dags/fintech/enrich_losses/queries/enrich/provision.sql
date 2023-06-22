SELECT 
  m.id_invoice,
  m.id_contract,
  m.accrual_year_month,
  m.deal_delay_rule_a,
  m.deal_delay_rule_b,
  m.deal_delay_rule_c,
  m.deal_delay_rule_d,
  m.deal_delay_rule_e,
  m.deal_order,
  m.deal_status, 
  m.delay_at_deal_creation,
  m.bigger_anchor_deal_at_contract,
  m.delay_contaminated_range_rule_a,
  m.delay_contaminated_range_rule_b,
  m.delay_contaminated_range_rule_c,
  m.delay_contaminated_range_rule_d,
  m.delay_contaminated_range_rule_e,
  m.delta_days,
  m.due_amount,
  m.frequency,
  m.full_delay_at_deal,
  m.guarantee_type,
  m.pd_range_rule_a,
  m.pd_range_rule_b,
  m.pd_range_rule_c,
  m.pd_range_rule_d,
  m.pd_range_rule_e,
  p1A.provision_factor*due_amount AS provision_balance_p1_delay_a,  
  p2A.provision_factor*due_amount AS provision_balance_p2_delay_a,  
  p3A.provision_factor*due_amount AS provision_balance_p3_delay_a,  
  p4A.provision_factor*due_amount AS provision_balance_p4_delay_a, 
  p1B.provision_factor*due_amount AS provision_balance_p1_delay_b,  
  p2B.provision_factor*due_amount AS provision_balance_p2_delay_b,  
  p3B.provision_factor*due_amount AS provision_balance_p3_delay_b,  
  p4B.provision_factor*due_amount AS provision_balance_p4_delay_b,   
  p1C.provision_factor*due_amount AS provision_balance_p1_delay_c,  
  p2C.provision_factor*due_amount AS provision_balance_p2_delay_c,  
  p3C.provision_factor*due_amount AS provision_balance_p3_delay_c,  
  p4C.provision_factor*due_amount AS provision_balance_p4_delay_c,   
  p1D.provision_factor*due_amount AS provision_balance_p1_delay_d,
  p2D.provision_factor*due_amount AS provision_balance_p2_delay_d,
  p3D.provision_factor*due_amount AS provision_balance_p3_delay_d,
  p4D.provision_factor*due_amount AS provision_balance_p4_delay_d,
  p1E.provision_factor*due_amount AS provision_balance_p1_delay_e,
  p2E.provision_factor*due_amount AS provision_balance_p2_delay_e,
  p3E.provision_factor*due_amount AS provision_balance_p3_delay_e,
  p4E.provision_factor*due_amount AS provision_balance_p4_delay_e,    
  m.risk_type,
  m.user,
  m.is_before_started,
  m.is_contract_with_deal,
  m.is_hr,
  m.is_invoice_deal,
  m.dt_closing,
  m.dt_created_deal,
  m.dt_due_adjs,
  m.dt_due_deal_anchor,
  m.dt_due_general_accrual,
  m.dt_paid_adjs,
  m.dt_snapshot
FROM 
  datalake_losses.delay as m
LEFT JOIN 
  datalake_losses.provision_factor AS p1D 
    ON (p1D.risk_type = m.risk_type) AND (p1D.pd_range = m.pd_range_rule_d) AND (p1D.sk_provision_rule=1)
LEFT JOIN 
  datalake_losses.provision_factor AS p2D 
    ON (p2D.risk_type = guarantee_type) AND (p2D.pd_range = m.pd_range_rule_d) AND (p2D.sk_provision_rule=2)
LEFT JOIN 
  datalake_losses.provision_factor AS p3D 
    ON (p3D.risk_type = guarantee_type) AND (p3D.pd_range = m.pd_range_rule_d) AND (p3D.sk_provision_rule=3)
LEFT JOIN 
  datalake_losses.provision_factor AS p4D 
    ON (p4D.risk_type = guarantee_type) AND (p4D.pd_range = m.pd_range_rule_d) AND (p4D.sk_provision_rule=4)
LEFT JOIN   
  datalake_losses.provision_factor AS p1B 
    ON (p1B.risk_type = m.risk_type) AND (p1B.pd_range = m.pd_range_rule_b) AND (p1B.sk_provision_rule=1)
LEFT JOIN 
  datalake_losses.provision_factor AS p2B 
    ON (p2B.risk_type = guarantee_type) AND (p2B.pd_range = m.pd_range_rule_b) AND (p2B.sk_provision_rule=2)
LEFT JOIN 
  datalake_losses.provision_factor AS p3B 
    ON (p3B.risk_type = guarantee_type) AND (p3B.pd_range = m.pd_range_rule_b) AND (p3B.sk_provision_rule=3)
LEFT JOIN 
  datalake_losses.provision_factor AS p4B 
    ON (p4B.risk_type = guarantee_type) AND (p4B.pd_range = m.pd_range_rule_b) AND (p4B.sk_provision_rule=4)
LEFT JOIN 
  datalake_losses.provision_factor AS p1A 
    ON (p1A.risk_type = m.risk_type) AND (p1A.pd_range = m.pd_range_rule_a) AND (p1A.sk_provision_rule=1)
LEFT JOIN 
  datalake_losses.provision_factor AS p2A 
    ON (p2A.risk_type = guarantee_type) AND (p2A.pd_range = m.pd_range_rule_a) AND (p2A.sk_provision_rule=2)
LEFT JOIN 
  datalake_losses.provision_factor AS p3A 
    ON (p3A.risk_type = guarantee_type) AND (p3A.pd_range = m.pd_range_rule_a) AND (p3A.sk_provision_rule=3)
LEFT JOIN 
  datalake_losses.provision_factor AS p4A 
    ON (p4A.risk_type = guarantee_type) AND (p4A.pd_range = m.pd_range_rule_a) AND (p4A.sk_provision_rule=4)
LEFT JOIN 
  datalake_losses.provision_factor AS p1C 
    ON (p1C.risk_type = m.risk_type) AND (p1C.pd_range = m.pd_range_rule_c) AND (p1C.sk_provision_rule=1)
LEFT JOIN 
  datalake_losses.provision_factor AS p2C 
    ON (p2C.risk_type = guarantee_type) AND (p2C.pd_range = m.pd_range_rule_c) AND (p2C.sk_provision_rule=2)
LEFT JOIN 
  datalake_losses.provision_factor AS p3C 
    ON (p3C.risk_type = guarantee_type) AND (p3C.pd_range = m.pd_range_rule_c) AND (p3C.sk_provision_rule=3)
LEFT JOIN 
  datalake_losses.provision_factor AS p4C 
    ON (p4C.risk_type = guarantee_type) AND (p4C.pd_range = m.pd_range_rule_c) AND (p4C.sk_provision_rule=4)
LEFT JOIN 
  datalake_losses.provision_factor AS p1E
    ON (p1E.risk_type = m.risk_type) AND (p1E.pd_range = m.pd_range_rule_e) AND (p1E.sk_provision_rule=1)
LEFT JOIN 
  datalake_losses.provision_factor AS p2E
    ON (p2E.risk_type = guarantee_type) AND (p2E.pd_range = m.pd_range_rule_e) AND (p2E.sk_provision_rule=2)
LEFT JOIN 
  datalake_losses.provision_factor AS p3E 
    ON (p3E.risk_type = guarantee_type) AND (p3E.pd_range = m.pd_range_rule_e) AND (p3E.sk_provision_rule=3)
LEFT JOIN 
  datalake_losses.provision_factor AS p4E 
    ON (p4E.risk_type = guarantee_type) AND (p4E.pd_range = m.pd_range_rule_e) AND (p4E.sk_provision_rule=4)