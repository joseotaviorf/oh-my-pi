/**
	Grants permissions on given schema for following groups:
		- data_heroes
		- looker
		- looker_marketing
		- metabase
		- metabase_marketing

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
	EXECUTE 'call grant_permissions_to_group(\'' || schema_name ||'\', \'metabase\');';
	EXECUTE 'call grant_permissions_to_group(\'' || schema_name ||'\', \'metabase_marketing\');';
	EXECUTE 'call grant_permissions_to_group(\'' || schema_name ||'\', \'looker\');';
	EXECUTE 'call grant_permissions_to_group(\'' || schema_name ||'\', \'looker_marketing\');';

	raise info 'All permissions granted on schema %;', schema_name;
end;
$$ language plpgsql;
