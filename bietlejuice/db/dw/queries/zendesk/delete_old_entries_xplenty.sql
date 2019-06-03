delete from zendesk.{table_name}
where {sk_field} in (select {sk_field} from staging.zendesk_{table_name})