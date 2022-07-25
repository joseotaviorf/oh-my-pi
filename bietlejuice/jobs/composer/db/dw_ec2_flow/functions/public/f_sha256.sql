CREATE OR REPLACE FUNCTION public.f_sha256(param character varying)
 RETURNS character varying LANGUAGE plpythonu
 STABLE
AS $$
	import hashlib
	if (param is None) or (param == ''):
		return None
	return hashlib.sha256(param).hexdigest()
$$;
