  SELECT
    distinct id_ticket as sk_ticket,
    replace(replace(t.tag, '[', ''), ']', '') as ticket_tag
  FROM datalake_clean.zendesk_tickets
  CROSS JOIN UNNEST(SPLIT(tags,',')) AS t (tag)