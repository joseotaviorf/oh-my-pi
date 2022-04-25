SELECT
    name AS user_name,
    last_name AS user_last_name,
    email AS user_email,
    phone AS user_phone,
    state AS user_state_code,
    analyst AS analyst_name,
    creci AS has_creci,
    CASE
      WHEN landing_page_complete_registration = 'Não' THEN False
      WHEN landing_page_complete_registration = 'Sim' THEN True
    END AS has_landing_page_complete_registration,
    CASE
      WHEN registred_as_afiliado_pro = 'Não' THEN False
      WHEN registred_as_afiliado_pro = 'Sim' THEN True
    END AS is_registred_as_affiliate_pro,
    CASE
      WHEN duplicated_sent_code = 'Não' THEN False
      WHEN duplicated_sent_code = 'Sim' THEN True
    END AS has_duplicated_sent_code,
    CASE
      WHEN asked_email_registration = 'Não' THEN False
      WHEN asked_email_registration = 'Sim' THEN True
    END AS has_asked_for_email_registration,
    CAST(date AS DATE) AS dt_acquired,
    CAST(contact_date AS DATE) AS dt_contacted
FROM
    datalake_gsheets_raw.affiliate_pro_registration