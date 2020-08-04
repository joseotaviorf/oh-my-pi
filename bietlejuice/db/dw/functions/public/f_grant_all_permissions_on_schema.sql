/**
	Grants permissions on given schema for following users and groups:
		- data_heroes
		- looker_full
		- looker_general
		- looker_marketing
		- metabase_general
		- metabase_full
		- general

  Call example:
      call grant_all_permissions_on_schema('my_new_cool_schema');

**/
create or replace procedure grant_all_permissions_on_schema(schema_name varchar)
as $$
begin
	IF schema_name is null THEN
		RAISE EXCEPTION 'The schema name cannot be null!';
	END IF;

	EXECUTE 'call grant_permissions_to_group(\'' || schema_name ||'\', \'data_heroes\');';
	EXECUTE 'call grant_permissions_to_group(\'' || schema_name ||'\', \'general\');';
	EXECUTE 'call grant_permissions_to_group(\'' || schema_name ||'\', \'metabase\');';

	EXECUTE 'call grant_permissions_to_user(\'' || schema_name ||'\', \'looker_full\');';
	EXECUTE 'call grant_permissions_to_user(\'' || schema_name ||'\', \'looker_general\');';
	EXECUTE 'call grant_permissions_to_user(\'' || schema_name ||'\', \'looker_marketing\');';

	raise info 'All permissions granted on schema %;', schema_name;
end;
$$ language plpgsql;
