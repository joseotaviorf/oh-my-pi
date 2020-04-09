/*
  Procedure that terminates (kill -9) locks in a specific table currently being queries in Redshift.
  It relies on the stat_activity table and the backend_pid procedure to correctly select the necessary pid to be killed.
  Also, it receives a parameter called 'specific_table' in order to exclude the given varchar from the users locking tables.

  Return: the number of locks released, only for the given table name.

  Call example:
      call terminate_locks_for_table('dim_region');

  !!!Attention!!! This procedure should only be used to kill locks in a certain table!
  !!!Attention!!! This procedure should be used with caution!
*/
create or replace procedure terminate_locks_for_table(specific_table in varchar)
as $$
declare
  locks_released integer := 0;
begin
	select into locks_released count(*)
	from (
		select
		  pg_terminate_backend(l.pid)
		from pg_locks l
		join pg_catalog.pg_class c
			on c.oid = l.relation
		join pg_catalog.pg_stat_activity a
			on a.procpid = l.pid
		where l.pid <> pg_backend_pid()
			and c.relname = specific_table
	);
	raise info 'Locks released for %: %', specific_table, locks_released;
end;
$$ language plpgsql;
