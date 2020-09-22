/**
	Grants permissions for given group on given schema
	Parameters:
		@schema varchar     - name of schema to be granted privilges
		@user_group varchar - group name which privilges will be granted
		@privilege varchar  - what privilege will be granted to group in the schema provided (ALL | SELECT)
	Returns:
		- void
	Call Example:
		- All privileges
			call grant_permissions_to_group('my_schema', 'etl', 'ALL')
		- Select Privilges
			call grant_permissions_to_group('my_schema', 'metabase', 'SELECT')

**/
CREATE OR REPLACE PROCEDURE public.sp_grant_permissions_to_group(schema_name VARCHAR, user_group VARCHAR, privilege VARCHAR)
LANGUAGE plpgsql
AS $$
BEGIN
	EXECUTE 'grant select on all tables in schema ' || schema_name || ' to group ' || user_group || ';';
	EXECUTE 'grant usage on schema ' || schema_name || ' to group ' || user_group  || ';';
	EXECUTE 'alter default privileges in schema ' || schema_name || ' grant '|| privilege ||' on tables to group ' || user_group  || ';';

	raise info 'Permissions successfully granted on schema % for group % (Privilge = %);', schema_name, user_group, privilege;
END;
$$;
