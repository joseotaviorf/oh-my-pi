/**
	Grants permissions for given user on given schema
**/
create or replace procedure grant_permissions_to_user(schema_name varchar, username varchar)
as $$
begin
	EXECUTE 'grant select on all tables in schema ' || schema_name || ' to ' || username || ';';
	EXECUTE 'grant usage on schema ' || schema_name || ' to ' || username  || ';';
	EXECUTE 'alter default privileges in schema ' || schema_name || ' grant select on tables to ' || username  || ';';

	raise info 'Permissions successfully granted on schema % for group %;', schema_name, username;
end;
$$ language plpgsql;