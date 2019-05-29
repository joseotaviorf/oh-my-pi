delete from zendesk.{table_name}
using staging.zendesk_{table_name}
where zendesk_{table_name}.{sk_field}={table_name}.{sk_field}
      and zendesk_{table_name}.ts_updated >= {table_name}.ts_updated;