def test_subject_model_routes_through_compatible_provider():
    from tars_evals.config import load_config
    from tars_evals.task import _CONFIG_PATH, _subject_model
    api = _subject_model(load_config(_CONFIG_PATH)).api
    # OpenAICompatibleAPI has NO is_latest/gpt-5 temperature-strip heuristic;
    # the real OpenAIAPI does. Asserting the type is the determinism guard.
    assert type(api).__name__ == "OpenAICompatibleAPI"
