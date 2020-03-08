/*
  Procedure that terminates (kill -9) locks in all tables currently being queries in Redshift. 
  It relies on the stat_activity table and the backend_pid procedure to correctly select the necessary pid to be killed.
  
  Return: the number of locks released.
  
  Call example:
      call terminate_all_locks();
  
  !!!Attention!!! This procedure should be used with caution!
*/
create or replace procedure terminate_all_locks()
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
	);
	raise info 'Locks released: %', locks_released;
end;
$$ language plpgsql;
