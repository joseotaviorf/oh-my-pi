/**
	Grants permissions for given group on given schema
**/
create or replace procedure grant_permissions_to_group(schema_name varchar, user_group varchar)
as $$
begin
	EXECUTE 'grant select on all tables in schema ' || schema_name || ' to group ' || user_group || ';';
	EXECUTE 'grant usage on schema ' || schema_name || ' to group ' || user_group  || ';';
	EXECUTE 'alter default privileges in schema ' || schema_name || ' grant select on tables to group ' || user_group  || ';';

	raise info 'Permissions successfully granted on schema % for group %;', schema_name, user_group;
end;
$$ language plpgsql;