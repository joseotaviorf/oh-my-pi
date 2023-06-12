SELECT 
  m.id_invoice,
  m.id_contract,
  m.accrual_year_month,
  m.deal_delay_rule_A,
  m.deal_delay_rule_B,
  m.deal_delay_rule_C,
  m.deal_delay_rule_D,
  m.deal_order,
  m.deal_status, 
  m.delay_at_deal_creation,
  m.delay_contaminated_range_rule_A,
  m.delay_contaminated_range_rule_B,
  m.delay_contaminated_range_rule_C,
  m.delay_contaminated_range_rule_D,
  m.delta_days,
  m.due_amount,
  m.frequency,
  m.full_delay_at_deal,
  m.guarantee_type,
  m.pd_range_rule_A,
  m.pd_range_rule_B,
  m.pd_range_rule_C,
  m.pd_range_rule_D,
  p1A.provision_factor*due_amount AS provision_balance_p1_delay_A,  
  p2A.provision_factor*due_amount AS provision_balance_p2_delay_A,  
  p3A.provision_factor*due_amount AS provision_balance_p3_delay_A,  
  p4A.provision_factor*due_amount AS provision_balance_p4_delay_A, 
  p1B.provision_factor*due_amount AS provision_balance_p1_delay_B,  
  p2B.provision_factor*due_amount AS provision_balance_p2_delay_B,  
  p3B.provision_factor*due_amount AS provision_balance_p3_delay_B,  
  p4B.provision_factor*due_amount AS provision_balance_p4_delay_B,   
  p1C.provision_factor*due_amount AS provision_balance_p1_delay_C,  
  p2C.provision_factor*due_amount AS provision_balance_p2_delay_C,  
  p3C.provision_factor*due_amount AS provision_balance_p3_delay_C,  
  p4C.provision_factor*due_amount AS provision_balance_p4_delay_C,   
  p1D.provision_factor*due_amount AS provision_balance_p1_delay_D,
  p2D.provision_factor*due_amount AS provision_balance_p2_delay_D,
  p3D.provision_factor*due_amount AS provision_balance_p3_delay_D,
  p4D.provision_factor*due_amount AS provision_balance_p4_delay_D,  
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
    ON (p1D.risk_type = m.risk_type) AND (p1D.pd_range = m.pd_range_rule_D) AND (p1D.sk_provision_rule=1)
LEFT JOIN 
  datalake_losses.provision_factor AS p2D 
    ON (p2D.risk_type = guarantee_type) AND (p2D.pd_range = m.pd_range_rule_D) AND (p2D.sk_provision_rule=2)
LEFT JOIN 
  datalake_losses.provision_factor AS p3D 
    ON (p3D.risk_type = guarantee_type) AND (p3D.pd_range = m.pd_range_rule_D) AND (p3D.sk_provision_rule=3)
LEFT JOIN 
  datalake_losses.provision_factor AS p4D 
    ON (p4D.risk_type = guarantee_type) AND (p4D.pd_range = m.pd_range_rule_D) AND (p4D.sk_provision_rule=4)
LEFT JOIN   
  datalake_losses.provision_factor AS p1B 
    ON (p1B.risk_type = m.risk_type) AND (p1B.pd_range = m.pd_range_rule_B) AND (p1B.sk_provision_rule=1)
LEFT JOIN 
  datalake_losses.provision_factor AS p2B 
    ON (p2B.risk_type = guarantee_type) AND (p2B.pd_range = m.pd_range_rule_B) AND (p2B.sk_provision_rule=2)
LEFT JOIN 
  datalake_losses.provision_factor AS p3B 
    ON (p3B.risk_type = guarantee_type) AND (p3B.pd_range = m.pd_range_rule_B) AND (p3B.sk_provision_rule=3)
LEFT JOIN 
  datalake_losses.provision_factor AS p4B 
    ON (p4B.risk_type = guarantee_type) AND (p4B.pd_range = m.pd_range_rule_B) AND (p4B.sk_provision_rule=4)
LEFT JOIN 
  datalake_losses.provision_factor AS p1A 
    ON (p1A.risk_type = m.risk_type) AND (p1A.pd_range = m.pd_range_rule_A) AND (p1A.sk_provision_rule=1)
LEFT JOIN 
  datalake_losses.provision_factor AS p2A 
    ON (p2A.risk_type = guarantee_type) AND (p2A.pd_range = m.pd_range_rule_A) AND (p2A.sk_provision_rule=2)
LEFT JOIN 
  datalake_losses.provision_factor AS p3A 
    ON (p3A.risk_type = guarantee_type) AND (p3A.pd_range = m.pd_range_rule_A) AND (p3A.sk_provision_rule=3)
LEFT JOIN 
  datalake_losses.provision_factor AS p4A 
    ON (p4A.risk_type = guarantee_type) AND (p4A.pd_range = m.pd_range_rule_A) AND (p4A.sk_provision_rule=4)
LEFT JOIN 
  datalake_losses.provision_factor AS p1C 
    ON (p1C.risk_type = m.risk_type) AND (p1C.pd_range = m.pd_range_rule_C) AND (p1C.sk_provision_rule=1)
LEFT JOIN 
  datalake_losses.provision_factor AS p2C 
    ON (p2C.risk_type = guarantee_type) AND (p2C.pd_range = m.pd_range_rule_C) AND (p2C.sk_provision_rule=2)
LEFT JOIN 
  datalake_losses.provision_factor AS p3C 
    ON (p3C.risk_type = guarantee_type) AND (p3C.pd_range = m.pd_range_rule_C) AND (p3C.sk_provision_rule=3)
LEFT JOIN 
  datalake_losses.provision_factor AS p4C 
    ON (p4C.risk_type = guarantee_type) AND (p4C.pd_range = m.pd_range_rule_C) AND (p4C.sk_provision_rule=4)