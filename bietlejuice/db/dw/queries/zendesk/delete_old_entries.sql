delete from zendesk.{table_name}
where sk_ticket in (select sk_ticket from staging.zendesk_{table_name})