 CREATE OR REPLACE FUNCTION replace_not_latin_chars(p_text text)
  RETURNS text AS
 $BODY$
 Select translate($1,
 'ÅåÄäĀāĄąȦȧÆæǢǣḂḃĆćĊċČčĘęËëȨȩḞḟĠġǦǧḦḧḨḩḰḱĹĺŁłḾḿṀṁØøÖöȮȯŔŕṘṙŚśŜŝẐẑẒẓẔẕŹźŻżŽžȤȥⱫⱬƵƶẊẋẌẍẎẏỾỿỲỳỴỵỶỷỸỹŶŷƳƴŸÿŞşṠṡṢṣŠšȘș',
 'AaAaAaAaAaAaAaBbCcCcCcEeEeEeFfGgGgHhHhKkLlLlMmMmOoOoOoRrRrSsSsZzZzZzZzZzZzZzZzZzXxXxYyYyYyYyYyYyYyYyYySsSsSsSsSs'
  );
 $BODY$
 LANGUAGE sql