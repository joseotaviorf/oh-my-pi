import mock

from bietlejuice.jobs.etl.planner import PlannerRegion, PlannerTableEnum


class TestPlannerRegion(object):

    @mock.patch.object(PlannerRegion, '_get_class_ids')
    def test_get_class_ids(self, mock__get_class_ids, planner_region):
        # act
        planner_region.get_class_ids()

        # assert
        mock__get_class_ids.assert_called_once_with(enum_type=PlannerTableEnum.REGION)

    @mock.patch.object(PlannerRegion, '_extract_data')
    def test_extract_data(self, mock__extract_data, planner_region):
        # arrange
        id_class = 1
        entity = PlannerTableEnum.REGION
        endpoint = 'http://planner.quintoandar.com.br/schedules/bi/region/{id_region}'

        # act
        planner_region.extract_data(id_class)

        # arrange
        mock__extract_data.assert_called_once_with(enum_type=entity,
                                                   endpoint=endpoint,
                                                   id_region=id_class)

    @mock.patch.object(PlannerRegion, '_save_into_s3_raw')
    def test_save_into_s3_raw(self, mock__save_into_s3_raw, planner_region):
        # arrange
        _json = {"visit": {"maxVisitsPerPool": 5, "properties": [{"position": 0, "id": 0}], "size": 2}, "schedules": {}}
        id_class = 1

        # act
        planner_region.save_into_s3_raw(_json, id_class)

        # assert
        mock__save_into_s3_raw.assert_called_once_with(_json=_json, enum_type=PlannerTableEnum.REGION,
                                                       id_class=id_class)

    @mock.patch.object(PlannerRegion, '_upsert_single_raw_partition')
    def test_upsert_single_raw_partition(self, mock__upsert_single_raw_partition, planner_region):
        # arrange
        id_class = 1

        # act
        planner_region.upsert_single_raw_partition(id_class)

        # assert
        mock__upsert_single_raw_partition.assert_called_once_with(enum_type=PlannerTableEnum.REGION,
                                                                  id_class=id_class)

    @mock.patch.object(PlannerRegion, '_upsert_single_clean_partition')
    def test_upsert_single_clean_partition(self, mock__upsert_single_clean_partition, planner_region):
        # arrange
        id_class = 1

        # act
        planner_region.upsert_single_clean_partition(id_class)

        # assert
        mock__upsert_single_clean_partition.assert_called_once_with(enum_type=PlannerTableEnum.REGION,
                                                                    id_class=id_class)

    @mock.patch.object(PlannerRegion, '_move_to_clean')
    def test_move_to_clean(self, mock__move_to_clean, planner_region):
        # arrange
        id_class = 1

        # act
        planner_region.move_to_clean(id_class)

        # assert
        assert mock__move_to_clean.call_count == 1
        assert mock__move_to_clean.call_args[1].get('enum_type') == PlannerTableEnum.REGION
        assert mock__move_to_clean.call_args[1].get('id_class') == id_class
