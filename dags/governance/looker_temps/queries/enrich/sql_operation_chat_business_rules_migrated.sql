WITH prep_lead_table AS (
  SELECT
    *,
    CASE
      WHEN department = 'WQa569814566ffbf89162f3f13c12f0bcc'
      THEN 'CX Mudança e Pagamento [FRONT] [POS]'
      WHEN department = 'WQ021e11049a5dec4aad894703c7e57e91'
      THEN 'CX Parceiros da Portaria [FRONT] [PRE]'
      WHEN department = 'WQ52b5dc92e73de3ae649bc6ebb89aedf8'
      THEN 'CX Programa Indica Ai [FRONT] [PRE]'
      WHEN department = 'WQ343503f5d3a9b44dfa52c09b51facbb9'
      THEN 'CX Propostas [FRONT] [PRE]'
      WHEN department = 'WQ47f4695d4ee74e8b5af47a90dd0feaa4'
      THEN 'CX Compra e Venda [FRONT] [PRE] [POS]'
      WHEN department = 'WQ9725cf862a8616c4570230b4cd8134b5'
      THEN 'CX Reparos [FRONT] [POS]'
      WHEN department = 'WQae4ce3bcc275b645c2a809d6f9c1216b'
      THEN 'CX Rescisão [FRONT] [POS]'
      WHEN department = 'WQ78bb33ed812c52c36587fe3b59449d43'
      THEN 'CX Suporte ao vistoriador [BACK] [POS]'
      WHEN department = 'WQa4224d6770e29544eb09b6f61dd6e271'
      THEN 'CX Visitas [FRONT] [PRE]'
      WHEN department = 'WQbb39d44c2521c9962a26aa709e719eda'
      THEN 'CX Vistoria [BACK]'
      WHEN department = 'WQf8fcefd8fab68705b28e83678282eb56'
      THEN 'Corretores de Relacionamento [B2B]'
      WHEN department = 'WQd633214ab1a585a3890172211e3fa188'
      THEN 'Everyone'
      WHEN department = 'WQf8fcefd8fab68705b28e83678282eb56'
      THEN 'Everyone'
      WHEN department = 'WQd1093ef738fcb896aec8a37c7b585584'
      THEN 'IS C2WA_Facebook [FRONT] [PRE]'
      WHEN department = 'WQa36a8033af77fa073c597baa4ead1242'
      THEN 'IS Compra e Venda [FRONT] [PRE]'
      WHEN department = 'WQ1769eb01f045e1c2e6520da84a695e60'
      THEN 'IS Confirmação de Fotos [BACK] [PRE]'
      WHEN department = 'WQ4a04644fc250255f877b422bbe6596d0'
      THEN 'IS Locação [FRONT] [PRE]'
      WHEN department = 'WQ59131d934f3065333d36ddfa7864fc22'
      THEN 'LOG Lockbox [BACK] [POS]'
      WHEN department = 'WQ25b8d57589df8c42e21e590545912f97'
      THEN 'CX Closing [BACK] [PRE]'
      WHEN department = 'WQ56ce30c639b20667ef14c03a9c4147ce'
      THEN 'CX Imobiliarias [FRONT] [PRE]'
      WHEN department = 'WQa231208510ee8b7dfc7bb74dfaefbc52'
      THEN 'CX Closing B2B [BACK] [PRE] [POS]'
      ELSE department
    END AS task_department
  FROM dw_quinto_messenger.dim_task
), lead_table AS (
  SELECT
    ft.sk_chat,
    dt.ts_created AS ts_task_created,
    RANK() OVER (PARTITION BY ft.sk_chat ORDER BY dt.ts_created NULLS LAST) AS task_number,
    ft.sk_task,
    dt.task_department,
    LAG(dt.task_department) OVER (PARTITION BY ft.sk_chat ORDER BY dt.ts_created NULLS LAST) AS prev_department,
    LEAD(dt.task_department) OVER (PARTITION BY ft.sk_chat ORDER BY dt.ts_created NULLS LAST) AS next_department,
    dt.completion_reason,
    qa.email,
    qa.location AS company,
    LEAD(qa.location) OVER (PARTITION BY ft.sk_chat ORDER BY dt.ts_created NULLS LAST) AS next_company
  FROM dw_quinto_messenger.fact_tasks AS ft
  INNER JOIN prep_lead_table AS dt
    ON dt.sk_task = ft.sk_task
  LEFT JOIN dw_quinto_messenger.dim_quinto_messenger_agent AS qa
    ON qa.sk_quinto_messenger_agent = ft.sk_quinto_messenger_agent
  ORDER BY
    1 NULLS LAST,
    2 NULLS LAST
), last_task_chat AS (
  SELECT
    fc.sk_chat,
    task_department AS chat_attributed_dept,
    email AS chat_attributed_email,
    company AS chat_attributed_company
  FROM lead_table
  INNER JOIN dw_quinto_messenger.fact_chats AS fc
    ON fc.sk_chat = lead_table.sk_chat
  WHERE
    fc.tasks = task_number
  ORDER BY
    1 NULLS LAST
)
SELECT
  CASE
    WHEN task_number = 1
    THEN TRUE
    WHEN prev_department <> lead_table.task_department
    THEN TRUE
    ELSE FALSE
  END AS first_in_dept,
  *
FROM lead_table
LEFT JOIN last_task_chat
  ON last_task_chat.sk_chat = lead_table.sk_chat