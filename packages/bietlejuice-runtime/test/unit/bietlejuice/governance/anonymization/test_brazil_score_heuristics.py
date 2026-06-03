from bietlejuice.governance.anonymization.brazil_score_heuristics import (
    apply_entity_score_floors_to_cleaned_results,
    should_keep_by_entity_score,
)


class TestShouldKeepByEntityScore:
    def test_person_above_floor(self):
        # arrange
        entity_type = "PERSON"
        score = 0.9

        # act
        keep = should_keep_by_entity_score(entity_type, score)

        # assert
        assert keep is True

    def test_person_below_floor(self):
        # arrange
        entity_type = "PERSON"
        score = 0.7

        # act
        keep = should_keep_by_entity_score(entity_type, score)

        # assert
        assert keep is False


class TestApplyEntityScoreFloors:
    def test_demotes_low_person_hit(self):
        # arrange
        cleaned = [{"type": "PERSON", "score": 0.7, "matched_value": "Acme Corp"}]

        # act
        result = apply_entity_score_floors_to_cleaned_results(cleaned)

        # assert
        assert result[0]["type"] == "NOT_FOUND"
