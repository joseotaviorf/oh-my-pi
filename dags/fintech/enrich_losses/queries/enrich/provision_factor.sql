SELECT
      1 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalCurrent' AS pd_range,
      'LR' AS risk_type,
      0.00605087 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      2 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalM +0 (1-30 days)' AS pd_range,
      'LR' AS risk_type,
      0.229993 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      3 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalM +1 (31-60 days)' AS pd_range,
      'LR' AS risk_type,
      0.540869 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      4 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalM +2 (61-90 days)' AS pd_range,
      'LR' AS risk_type,
      0.779398 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      5 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalM +3 (91-120 days)' AS pd_range,
      'LR' AS risk_type,
      1.0000 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      6 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalM +4 (121-150 days)' AS pd_range,
      'LR' AS risk_type,
      1.0000 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      7 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalM +5 (151-180 days)' AS pd_range,
      'LR' AS risk_type,
      1.0000 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      8 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalM +6 (>181 days)' AS pd_range,
      'LR' AS risk_type,
      1.0000 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      9 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalCurrent' AS pd_range,
      'HR' AS risk_type,
      0.456873 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      10 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalM +0 (1-30 days)' AS pd_range,
      'HR' AS risk_type,
      0.96691 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      11 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalM +1 (31-60 days)' AS pd_range,
      'HR' AS risk_type,
      1.0000 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      12 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalM +2 (61-90 days)' AS pd_range,
      'HR' AS risk_type,
      1.0000 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      13 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalM +3 (91-120 days)' AS pd_range,
      'HR' AS risk_type,
      1.0000 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      14 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalM +4 (121-150 days)' AS pd_range,
      'HR' AS risk_type,
      1.0000 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      15 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalM +5 (151-180 days)' AS pd_range,
      'HR' AS risk_type,
      1.0000 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      16 AS sk_factor_risk,
      1 AS sk_provision_rule,
      'TotalM +6 (>181 days)' AS pd_range,
      'HR' AS risk_type,
      1.0000 AS provision_factor,
      '2022-01-01' AS begin_date_application,
      '2023-01-01' AS end_date_application,
      'high-low-risk'	AS provision_name
  UNION ALL
  SELECT
      17 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalCurrent' AS pd_range,
      'FREE' AS risk_type,
      0.016543 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      18 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalM +0 (1-30 days)' AS pd_range,
      'FREE' AS risk_type,
      0.457365 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      19 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalM +1 (31-60 days)' AS pd_range,
      'FREE' AS risk_type,
      0.822112 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      20 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalM +2 (61-90 days)' AS pd_range,
      'FREE' AS risk_type,
      1.0000 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      21 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalM +3 (91-120 days)' AS pd_range,
      'FREE' AS risk_type,
      1.0000 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      22 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalM +4 (121-150 days)' AS pd_range,
      'FREE' AS risk_type,
      1.0000 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      23 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalM +5 (151-180 days)' AS pd_range,
      'FREE' AS risk_type,
      1.0000 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      24 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalM +6 (>181 days)' AS pd_range,
      'FREE' AS risk_type,
      1.0000 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      25 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalCurrent' AS pd_range,
      'PAID' AS risk_type,
      0.075263 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      26 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalM +0 (1-30 days)' AS pd_range,
      'PAID' AS risk_type,
      0.586976 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      27 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalM +1 (31-60 days)' AS pd_range,
      'PAID' AS risk_type,
      0.947956 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      28 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalM +2 (61-90 days)' AS pd_range,
      'PAID' AS risk_type,
      1.0000 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      29 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalM +3 (91-120 days)' AS pd_range,
      'PAID' AS risk_type,
      1.0000 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      30 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalM +4 (121-150 days)' AS pd_range,
      'PAID' AS risk_type,
      1.0000 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      31 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalM +5 (151-180 days)' AS pd_range,
      'PAID' AS risk_type,
      1.0000 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      32 AS sk_factor_risk,
      2 AS sk_provision_rule,
      'TotalM +6 (>181 days)' AS pd_range,
      'PAID' AS risk_type,
      1.0000 AS provision_factor,
      '2023-01-01' AS begin_date_application,
      '2023-02-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      33 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalCurrent' AS pd_range,
      'FREE' AS risk_type,
      0.01763597 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      34 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalM +0 (1-30 days)' AS pd_range,
      'FREE' AS risk_type,
      0.49469504 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      35 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalM +1 (31-60 days)' AS pd_range,
      'FREE' AS risk_type,
      0.84884854 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      36 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalM +2 (61-90 days)' AS pd_range,
      'FREE' AS risk_type,
      1.0000 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      37 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalM +3 (91-120 days)' AS pd_range,
      'FREE' AS risk_type,
      1.0000 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      38 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalM +4 (121-150 days)' AS pd_range,
      'FREE' AS risk_type,
      1.0000 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      39 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalM +5 (151-180 days)' AS pd_range,
      'FREE' AS risk_type,
      1.0000 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      40 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalM +6 (>181 days)' AS pd_range,
      'FREE' AS risk_type,
      1.0000 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      41 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalCurrent' AS pd_range,
      'PAID' AS risk_type,
      0.080674 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      42 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalM +0 (1-30 days)' AS pd_range,
      'PAID' AS risk_type,
      0.640917 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      43 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalM +1 (31-60 days)' AS pd_range,
      'PAID' AS risk_type,
      0.983641 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      44 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalM +2 (61-90 days)' AS pd_range,
      'PAID' AS risk_type,
      1.0000 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      45 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalM +3 (91-120 days)' AS pd_range,
      'PAID' AS risk_type,
      1.0000 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      46 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalM +4 (121-150 days)' AS pd_range,
      'PAID' AS risk_type,
      1.0000 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      47 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalM +5 (151-180 days)' AS pd_range,
      'PAID' AS risk_type,
      1.0000 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      48 AS sk_factor_risk,
      3 AS sk_provision_rule,
      'TotalM +6 (>181 days)' AS pd_range,
      'PAID' AS risk_type,
      1.0000 AS provision_factor,
      '2023-02-01' AS begin_date_application,
      '2023-03-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      49 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalCurrent' AS pd_range,
      'FREE' AS risk_type,
      0.0173028218787078 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      50 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalM +0 (1-30 days)' AS pd_range,
      'FREE' AS risk_type,
      0.483213691136929 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      51 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalM +1 (31-60 days)' AS pd_range,
      'FREE' AS risk_type,
      0.844241325699331 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      52 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalM +2 (61-90 days)' AS pd_range,
      'FREE' AS risk_type,
      1.0000 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      53 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalM +3 (91-120 days)' AS pd_range,
      'FREE' AS risk_type,
      1.0000 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      54 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalM +4 (121-150 days)' AS pd_range,
      'FREE' AS risk_type,
      1.0000 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      55 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalM +5 (151-180 days)' AS pd_range,
      'FREE' AS risk_type,
      1.0000 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      56 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalM +6 (>181 days)' AS pd_range,
      'FREE' AS risk_type,
      1.0000 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      57 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalCurrent' AS pd_range,
      'PAID' AS risk_type,
      0.0798048140582744 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      58 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalM +0 (1-30 days)' AS pd_range,
      'PAID' AS risk_type,
      0.628938565860829 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      59 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalM +1 (31-60 days)' AS pd_range,
      'PAID' AS risk_type,
      0.973657406442979 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      60 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalM +2 (61-90 days)' AS pd_range,
      'PAID' AS risk_type,
      1.0000 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      61 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalM +3 (91-120 days)' AS pd_range,
      'PAID' AS risk_type,
      1.0000 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      62 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalM +4 (121-150 days)' AS pd_range,
      'PAID' AS risk_type,
      1.0000 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      63 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalM +5 (151-180 days)' AS pd_range,
      'PAID' AS risk_type,
      1.0000 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
  UNION ALL
  SELECT
      64 AS sk_factor_risk,
      4 AS sk_provision_rule,
      'TotalM +6 (>181 days)' AS pd_range,
      'PAID' AS risk_type,
      1.0000 AS provision_factor,
      '2023-03-01' AS begin_date_application,
      '2023-11-01' AS end_date_application,
      'guarantee'	AS provision_name
    UNION ALL
    SELECT
        65 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalCurrent' AS pd_range,
        'FREE' AS risk_type,
        0.0165273443749487 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        66 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalM +0 (1-30 days)' AS pd_range,
        'FREE' AS risk_type,
        0.437770133545829 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        67 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalM +1 (31-60 days)' AS pd_range,
        'FREE' AS risk_type,
        0.702923823249957 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        68 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalM +2 (61-90 days)' AS pd_range,
        'FREE' AS risk_type,
        1.0000 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        69 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalM +3 (91-120 days)' AS pd_range,
        'FREE' AS risk_type,
        1.0000 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        70 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalM +4 (121-150 days)' AS pd_range,
        'FREE' AS risk_type,
        1.0000 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        71 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalM +5 (151-180 days)' AS pd_range,
        'FREE' AS risk_type,
        1.0000 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        72 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalM +6 (>181 days)' AS pd_range,
        'FREE' AS risk_type,
        1.0000 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        73 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalCurrent' AS pd_range,
        'PAID' AS risk_type,
        0.0753916667348127 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        74 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalM +0 (1-30 days)' AS pd_range,
        'PAID' AS risk_type,
        0.610973390591814 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        75 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalM +1 (31-60 days)' AS pd_range,
        'PAID' AS risk_type,
        0.838032150437293 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        76 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalM +2 (61-90 days)' AS pd_range,
        'PAID' AS risk_type,
        1.0000 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        77 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalM +3 (91-120 days)' AS pd_range,
        'PAID' AS risk_type,
        1.0000 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        78 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalM +4 (121-150 days)' AS pd_range,
        'PAID' AS risk_type,
        1.0000 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        79 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalM +5 (151-180 days)' AS pd_range,
        'PAID' AS risk_type,
        1.0000 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        80 AS sk_factor_risk,
        5 AS sk_provision_rule,
        'TotalM +6 (>181 days)' AS pd_range,
        'PAID' AS risk_type,
        1.0000 AS provision_factor,
        '2023-12-01' AS begin_date_application,
        '2024-06-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        81 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalCurrent' AS pd_range,
        'FREE' AS risk_type,
        0.0140 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        82 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalM +0 (1-30 days)' AS pd_range,
        'FREE' AS risk_type,
        0.3764 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        83 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalM +1 (31-60 days)' AS pd_range,
        'FREE' AS risk_type,
        0.6805 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        84 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalM +2 (61-90 days)' AS pd_range,
        'FREE' AS risk_type,
        1.0000 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        85 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalM +3 (91-120 days)' AS pd_range,
        'FREE' AS risk_type,
        1.0000 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        86 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalM +4 (121-150 days)' AS pd_range,
        'FREE' AS risk_type,
        1.0000 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        87 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalM +5 (151-180 days)' AS pd_range,
        'FREE' AS risk_type,
        1.0000 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        88 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalM +6 (>181 days)' AS pd_range,
        'FREE' AS risk_type,
        1.0000 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        89 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalCurrent' AS pd_range,
        'PAID' AS risk_type,
        0.0750 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        90 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalM +0 (1-30 days)' AS pd_range,
        'PAID' AS risk_type,
        0.5822 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        91 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalM +1 (31-60 days)' AS pd_range,
        'PAID' AS risk_type,
        0.8393 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        92 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalM +2 (61-90 days)' AS pd_range,
        'PAID' AS risk_type,
        1.0000 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        93 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalM +3 (91-120 days)' AS pd_range,
        'PAID' AS risk_type,
        1.0000 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        94 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalM +4 (121-150 days)' AS pd_range,
        'PAID' AS risk_type,
        1.0000 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        95 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalM +5 (151-180 days)' AS pd_range,
        'PAID' AS risk_type,
        1.0000 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
    UNION ALL
    SELECT
        96 AS sk_factor_risk,
        6 AS sk_provision_rule,
        'TotalM +6 (>181 days)' AS pd_range,
        'PAID' AS risk_type,
        1.0000 AS provision_factor,
        '2024-07-01' AS begin_date_application,
        '2024-12-01' AS end_date_application,
        'guarantee'	AS provision_name
