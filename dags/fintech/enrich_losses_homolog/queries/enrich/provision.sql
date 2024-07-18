WITH provision AS(
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
    CASE
      WHEN m.user = 'tenant' THEN 'Inquilino'
      WHEN m.user = 'landlord' THEN 'Proprietario'
      ELSE ''
    END AS invoice_account_type,
    payment_status,
    CASE
      WHEN m.payment_status = 'paid' THEN 'Pago'
      WHEN m.payment_status = 'open' THEN 'Em aberto'
      WHEN m.payment_status = 'canceled' THEN 'Cancelado'
      WHEN m.payment_status = 'written down' THEN 'Baixado'
      ELSE m.payment_status
    END AS invoice_status,
    m.pd_range_rule_a,
    m.pd_range_rule_b,
    m.pd_range_rule_c,
    m.pd_range_rule_d,
    m.pd_range_rule_e,
    p1A.provision_factor * due_amount AS provision_balance_p1_delay_a,
    p2A.provision_factor * due_amount AS provision_balance_p2_delay_a,
    p3A.provision_factor * due_amount AS provision_balance_p3_delay_a,
    p4A.provision_factor * due_amount AS provision_balance_p4_delay_a,
    p5A.provision_factor * due_amount AS provision_balance_p5_delay_a,
    p1B.provision_factor * due_amount AS provision_balance_p1_delay_b,
    p2B.provision_factor * due_amount AS provision_balance_p2_delay_b,
    p3B.provision_factor * due_amount AS provision_balance_p3_delay_b,
    p4B.provision_factor * due_amount AS provision_balance_p4_delay_b,
    p5B.provision_factor * due_amount AS provision_balance_p5_delay_b,
    p1C.provision_factor * due_amount AS provision_balance_p1_delay_c,
    p2C.provision_factor * due_amount AS provision_balance_p2_delay_c,
    p3C.provision_factor * due_amount AS provision_balance_p3_delay_c,
    p4C.provision_factor * due_amount AS provision_balance_p4_delay_c,
    p5C.provision_factor * due_amount AS provision_balance_p5_delay_c,
    p1D.provision_factor * due_amount AS provision_balance_p1_delay_d,
    p2D.provision_factor * due_amount AS provision_balance_p2_delay_d,
    p3D.provision_factor * due_amount AS provision_balance_p3_delay_d,
    p4D.provision_factor * due_amount AS provision_balance_p4_delay_d,
    p5D.provision_factor * due_amount AS provision_balance_p5_delay_d,
    p1E.provision_factor * due_amount AS provision_balance_p1_delay_e,
    p2E.provision_factor * due_amount AS provision_balance_p2_delay_e,
    p3E.provision_factor * due_amount AS provision_balance_p3_delay_e,
    p4E.provision_factor * due_amount AS provision_balance_p4_delay_e,
    p5E.provision_factor * due_amount AS provision_balance_p5_delay_e,
    CASE
      WHEN DATE_TRUNC('month', dt_snapshot) - INTERVAL '1' MONTH <= DATE('2022-11-01') THEN p1B.provision_factor
      WHEN DATE_TRUNC('month', dt_snapshot) - INTERVAL '1' MONTH = DATE('2022-12-01') THEN p4B.provision_factor
      WHEN DATE_TRUNC('month', dt_snapshot) - INTERVAL '1' MONTH = DATE('2023-01-01') THEN p2A.provision_factor
      WHEN DATE_TRUNC('month', dt_snapshot) - INTERVAL '1' MONTH = DATE('2023-02-01') THEN p3B.provision_factor
      WHEN DATE_TRUNC('month', dt_snapshot) - INTERVAL '1' MONTH BETWEEN DATE('2023-03-01') AND DATE('2023-05-01') THEN p4B.provision_factor
      WHEN DATE_TRUNC('month', dt_snapshot) - INTERVAL '1' MONTH BETWEEN DATE('2023-06-01') AND DATE('2023-11-01') THEN p4E.provision_factor
      WHEN DATE_TRUNC('month', dt_snapshot) - INTERVAL '1' MONTH >= DATE('2023-12-01') THEN p5E.provision_factor
    END AS provision_factor,
    m.risk_type,
    m.user,
    m.is_before_started,
    m.is_contract_with_deal,
    m.is_hr,
    m.is_invoice_deal,
    m.is_international,
    m.is_writtendown_in_dead_time,
    m.has_repair_offboarding_bill_item,
    m.dt_closing,
    m.dt_created_deal,
    m.dt_due_adjs,
    m.dt_due_deal_anchor,
    m.dt_due_general_accrual,
    m.dt_paid_adjs,
    m.dt_snapshot
  FROM datalake_losses_homolog.delay AS m
    LEFT JOIN datalake_losses_homolog.provision_factor AS p1D
      ON (p1D.risk_type = m.risk_type)
      AND (p1D.pd_range = m.pd_range_rule_d)
      AND (p1D.sk_provision_rule = 1)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p2D
      ON (p2D.risk_type = guarantee_type)
      AND (p2D.pd_range = m.pd_range_rule_d)
      AND (p2D.sk_provision_rule = 2)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p3D
      ON (p3D.risk_type = guarantee_type)
      AND (p3D.pd_range = m.pd_range_rule_d)
      AND (p3D.sk_provision_rule = 3)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p4D
      ON (p4D.risk_type = guarantee_type)
      AND (p4D.pd_range = m.pd_range_rule_d)
      AND (p4D.sk_provision_rule = 4)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p5D
      ON (p5D.risk_type = guarantee_type)
      AND (p5D.pd_range = m.pd_range_rule_d)
      AND (p5D.sk_provision_rule = 5)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p1B
      ON (p1B.risk_type = m.risk_type)
      AND (p1B.pd_range = m.pd_range_rule_b)
      AND (p1B.sk_provision_rule = 1)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p2B
      ON (p2B.risk_type = guarantee_type)
      AND (p2B.pd_range = m.pd_range_rule_b)
      AND (p2B.sk_provision_rule = 2)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p3B
      ON (p3B.risk_type = guarantee_type)
      AND (p3B.pd_range = m.pd_range_rule_b)
      AND (p3B.sk_provision_rule = 3)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p4B
      ON (p4B.risk_type = guarantee_type)
      AND (p4B.pd_range = m.pd_range_rule_b)
      AND (p4B.sk_provision_rule = 4)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p5B
      ON (p5B.risk_type = guarantee_type)
      AND (p5B.pd_range = m.pd_range_rule_b)
      AND (p5B.sk_provision_rule = 5)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p1A
      ON (p1A.risk_type = m.risk_type)
      AND (p1A.pd_range = m.pd_range_rule_a)
      AND (p1A.sk_provision_rule = 1)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p2A
      ON (p2A.risk_type = guarantee_type)
      AND (p2A.pd_range = m.pd_range_rule_a)
      AND (p2A.sk_provision_rule = 2)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p3A
      ON (p3A.risk_type = guarantee_type)
      AND (p3A.pd_range = m.pd_range_rule_a)
      AND (p3A.sk_provision_rule = 3)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p4A
      ON (p4A.risk_type = guarantee_type)
      AND (p4A.pd_range = m.pd_range_rule_a)
      AND (p4A.sk_provision_rule = 4)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p5A
      ON (p5A.risk_type = guarantee_type)
      AND (p5A.pd_range = m.pd_range_rule_a)
      AND (p5A.sk_provision_rule = 5)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p1C
      ON (p1C.risk_type = m.risk_type)
      AND (p1C.pd_range = m.pd_range_rule_c)
      AND (p1C.sk_provision_rule = 1)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p2C
      ON (p2C.risk_type = guarantee_type)
      AND (p2C.pd_range = m.pd_range_rule_c)
      AND (p2C.sk_provision_rule = 2)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p3C
      ON (p3C.risk_type = guarantee_type)
      AND (p3C.pd_range = m.pd_range_rule_c)
      AND (p3C.sk_provision_rule = 3)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p4C
      ON (p4C.risk_type = guarantee_type)
      AND (p4C.pd_range = m.pd_range_rule_c)
      AND (p4C.sk_provision_rule = 4)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p5C
      ON (p5C.risk_type = guarantee_type)
      AND (p5C.pd_range = m.pd_range_rule_c)
      AND (p5C.sk_provision_rule = 5)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p1E
      ON (p1E.risk_type = m.risk_type)
      AND (p1E.pd_range = m.pd_range_rule_e)
      AND (p1E.sk_provision_rule = 1)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p2E
      ON (p2E.risk_type = guarantee_type)
      AND (p2E.pd_range = m.pd_range_rule_e)
      AND (p2E.sk_provision_rule = 2)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p3E
      ON (p3E.risk_type = guarantee_type)
      AND (p3E.pd_range = m.pd_range_rule_e)
      AND (p3E.sk_provision_rule = 3)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p4E
      ON (p4E.risk_type = guarantee_type)
      AND (p4E.pd_range = m.pd_range_rule_e)
      AND (p4E.sk_provision_rule = 4)
    LEFT JOIN datalake_losses_homolog.provision_factor AS p5E
      ON (p5E.risk_type = guarantee_type)
      AND (p5E.pd_range = m.pd_range_rule_e)
      AND (p5E.sk_provision_rule = 5)
)
SELECT
  id_invoice,
  id_contract,
  accrual_year_month,
  deal_delay_rule_a,
  deal_delay_rule_b,
  deal_delay_rule_c,
  deal_delay_rule_d,
  deal_delay_rule_e,
  deal_order,
  deal_status,
  delay_at_deal_creation,
  bigger_anchor_deal_at_contract,
  delay_contaminated_range_rule_a,
  delay_contaminated_range_rule_b,
  delay_contaminated_range_rule_c,
  delay_contaminated_range_rule_d,
  delay_contaminated_range_rule_e,
  delta_days,
  due_amount,
  frequency,
  full_delay_at_deal,
  guarantee_type,
  invoice_account_type,
  payment_status,
  invoice_status,
  pd_range_rule_a,
  pd_range_rule_b,
  pd_range_rule_c,
  pd_range_rule_d,
  pd_range_rule_e,
  provision_balance_p1_delay_a,
  provision_balance_p2_delay_a,
  provision_balance_p3_delay_a,
  provision_balance_p4_delay_a,
  provision_balance_p5_delay_a,
  provision_balance_p1_delay_b,
  provision_balance_p2_delay_b,
  provision_balance_p3_delay_b,
  provision_balance_p4_delay_b,
  provision_balance_p5_delay_b,
  provision_balance_p1_delay_c,
  provision_balance_p2_delay_c,
  provision_balance_p3_delay_c,
  provision_balance_p4_delay_c,
  provision_balance_p5_delay_c,
  provision_balance_p1_delay_d,
  provision_balance_p2_delay_d,
  provision_balance_p3_delay_d,
  provision_balance_p4_delay_d,
  provision_balance_p5_delay_d,
  provision_balance_p1_delay_e,
  provision_balance_p2_delay_e,
  provision_balance_p3_delay_e,
  provision_balance_p4_delay_e,
  provision_balance_p5_delay_e,
  CASE
    WHEN date_trunc('month', dt_snapshot) - interval '1' month <= DATE('2022-11-01') THEN provision_balance_p1_delay_b
    WHEN date_trunc('month', dt_snapshot) - interval '1' month = DATE('2022-12-01') THEN provision_balance_p4_delay_b
    WHEN date_trunc('month', dt_snapshot) - interval '1' month = DATE('2023-01-01') THEN provision_balance_p2_delay_a
    WHEN date_trunc('month', dt_snapshot) - interval '1' month = DATE('2023-02-01') THEN provision_balance_p3_delay_b
    WHEN date_trunc('month', dt_snapshot) - interval '1' month BETWEEN DATE('2023-03-01') AND DATE('2023-05-01') THEN provision_balance_p4_delay_b
    WHEN date_trunc('month', dt_snapshot) - interval '1' month BETWEEN DATE('2023-06-01') AND DATE('2023-11-01') THEN provision_balance_p4_delay_e
    WHEN date_trunc('month', dt_snapshot) - interval '1' month >= DATE('2023-12-01') THEN provision_balance_p5_delay_e
  END AS provision_balance,
  provision_factor,
  risk_type,
  user,
  is_before_started,
  is_contract_with_deal,
  is_hr,
  is_invoice_deal,
  is_international,
  is_writtendown_in_dead_time,
  has_repair_offboarding_bill_item,
  dt_closing,
  dt_created_deal,
  dt_due_adjs,
  dt_due_deal_anchor,
  dt_due_general_accrual,
  dt_paid_adjs,
  dt_snapshot
FROM provision
