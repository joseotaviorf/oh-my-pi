/*
  Procedure that terminates (kill -9) locks in all tables currently being queries in Redshift. 
  It relies on the stat_activity table and the backend_pid procedure to correctly select the necessary pid to be killed.
  Also, it receives a parameter called 'except_user' in order to exclude the given varchar from the users locking tables.
  
  Return: the number of locks released, except for the given user.
  
  Call example:
      call terminate_locks_for_user('airflow');
  
  !!!Attention!!! This procedure should only be used to favor a certain user!
*/
create or replace procedure terminate_locks_for_user(except_user in varchar)
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
			and a.usename != except_user
	);
	raise info 'Locks released for %: %', except_user, locks_released;
end;
$$ language plpgsql;
