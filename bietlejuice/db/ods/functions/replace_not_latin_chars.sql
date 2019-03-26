CREATE OR REPLACE FUNCTION replace_not_latin_chars(p_text text)
  RETURNS text AS
 $BODY$
 Select translate($1,
 'ẐẑẒẓẔẕŹźŻżŽžȤȥⱫⱬƵƶẊẋẌẍẎẏỾỿỲỳỴỵỶỷỸỹŶŷƳƴŸÿ',
 'ZzZzZzZzZzZzZzZzZzXxXxYyYyYyYyYyYyYyYyYy'
  );
 $BODY$
 LANGUAGE sql