 CREATE OR REPLACE FUNCTION replace_not_latin_chars(p_text text)
  RETURNS text AS
 $BODY$
 Select regexp_replace($1,'[^\x00-\x7F^ÁáÂâÃãÉéÊêÍíÓóÔôÕõÚúÇçÀà]+', '', 'g'
  );
 $BODY$
 LANGUAGE sql