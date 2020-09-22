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
CREATE OR REPLACE PROCEDURE public.sp_grant_select_permissions_on_schema(schema_name VARCHAR)
AS $$
BEGIN
	IF schema_name is null THEN
		RAISE EXCEPTION 'The schema name cannot be null!';
	END IF;

	EXECUTE 'call grant_permissions_to_group(\'' || schema_name ||'\', \'data_heroes\', \'SELECT\');';
	EXECUTE 'call grant_permissions_to_group(\'' || schema_name ||'\', \'metabase\', \'SELECT\');';
	EXECUTE 'call grant_permissions_to_group(\'' || schema_name ||'\', \'metabase_marketing\', \'SELECT\');';
	EXECUTE 'call grant_permissions_to_group(\'' || schema_name ||'\', \'looker\', \'SELECT\');';
	EXECUTE 'call grant_permissions_to_group(\'' || schema_name ||'\', \'looker_marketing\', \'SELECT\');';

	raise info 'Select privileges granted on schema %;', schema_name;
END;
$$ LANGUAGE plpgsql ;
