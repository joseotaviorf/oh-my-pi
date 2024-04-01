SELECT
   id_service,
   prompts.prompt,
   regexp_replace(service_version, "[^0-9a-zA-Z_\-]+", "_") as service_version,
   keys.session_id,
   keys.userId as id_user,
   keys.pipeline,
   keys.llm_model,
   keys.prompt_faqs,
   keys.top_5_faqs,
   keys.score,
   keys.prompt_token_length,
   keys.response_token_length,
   keys.retrieval_response_time.start as retrieval_response_time_start,
   keys.retrieval_response_time.finish as retrieval_response_time_finish,
   keys.retrieval_response_time.total as retrieval_response_time_total,
   keys.generator_response_time.start as generator_response_time_start,
   keys.generator_response_time.finish as generator_response_time_finish,
   keys.generator_response_time.total as generator_response_time_total,
   keys.total_response_time,
   keys.test_ab_flags.is_experimental_prompt_enabled,
   keys.test_ab_flags.is_gpt_4_experimental_enabled,
   outp.result,
   year,
   month,
   day
FROM (
    SELECT
       id_service,
       year(ts_log) as year,
       month(ts_log) as month,
       day(ts_log) as day,
       FROM_JSON(inputs, "Struct<prompt: STRING>") as prompts,
       FROM_JSON(service_keys, "Struct<session_id: LONG,
                                        userId: LONG,
                                        pipeline: STRING,
                                        llm_model: STRING,
                                        prompt_faqs: Array<Struct<id: STRING, title: STRING>>,
                                        top_5_faqs: Array<Struct<id: STRING, title: STRING>>,
                                        score: DOUBLE, prompt_token_length: INT,
                                        response_token_length: INT,
                                        retrieval_response_time: Struct<start: STRING, finish: STRING, total: DOUBLE>,
                                        generator_response_time: Struct<start: STRING, finish: STRING, total: DOUBLE>,
                                        total_response_time: DOUBLE,
                                        test_ab_flags: Struct<is_experimental_prompt_enabled: BOOLEAN,
                                        is_gpt_4_experimental_enabled: BOOLEAN>>") as keys,
       FROM_JSON(outputs, "Struct<result: STRING>") as outp,
       service_version
    FROM
       datalake_emlio_clean.emlio_logs
    WHERE
       year = {year}
       AND month = {month}
       AND day = {day}
       AND id_service = 'emma_watson'
)
