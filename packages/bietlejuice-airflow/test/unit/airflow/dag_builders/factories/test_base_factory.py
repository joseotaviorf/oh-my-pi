from unittest import mock

import pytest

from bietlejuice.base.airflow.dag_builders.main_builder.factories.base_factory import (
    BaseFactory,
)


class TestBaseFactory:
    def test___workflow_enum_to_class_mapping_default_value_is_dict(self):
        assert hasattr(BaseFactory, "_BaseFactory__WORKFLOW_ENUM_TO_CLASS_MAPPING")
        assert BaseFactory._BaseFactory__WORKFLOW_ENUM_TO_CLASS_MAPPING == {}

    def test_base_factory_is_base_class(self):
        # arrange
        class TestFactory(BaseFactory):
            def concrete_method():
                pass

        # assert
        with pytest.raises(TypeError):
            _ = TestFactory()

    def test__workflow_enum_to_class_mapping_getter(self, base_factory):
        # act & assert
        assert (
            base_factory._WORKFLOW_ENUM_TO_CLASS_MAPPING
            == base_factory._BaseFactory__WORKFLOW_ENUM_TO_CLASS_MAPPING
        )

    @pytest.mark.parametrize("new_mapping_value", [{"TEST": "TEST"}, {"a": 1, "b": 2}])
    def test__workflow_enum_to_class_mapping_setter(
        self, new_mapping_value, base_factory
    ):
        # act
        base_factory._WORKFLOW_ENUM_TO_CLASS_MAPPING = new_mapping_value

        # assert
        assert base_factory._WORKFLOW_ENUM_TO_CLASS_MAPPING == new_mapping_value

    @pytest.mark.parametrize("new_mapping_value", ["ANY_STRING", [], "", callable, {}])
    @mock.patch.object(
        BaseFactory,
        "_BaseFactory__WORKFLOW_ENUM_TO_CLASS_MAPPING",
        new_callable=mock.PropertyMock,
    )
    def test__workflow_enum_to_class_mapping_setter_raises_runtime_error(
        self,
        mocked_basefactory__workflow_enum_to_class_mapping,
        new_mapping_value,
        base_factory,
    ):
        # arrange
        mocked_basefactory__workflow_enum_to_class_mapping.return_value = {
            "ENUM_MEMBER": "WORKFLOW_CLASS"
        }
        # act & assert
        with pytest.raises(
            RuntimeError, match="You can't change the workflow mapping during runtime."
        ):
            base_factory._WORKFLOW_ENUM_TO_CLASS_MAPPING = new_mapping_value

    @pytest.mark.parametrize("new_mapping_value", ["ANY_STRING", [], "", callable])
    @mock.patch.object(
        BaseFactory,
        "_BaseFactory__WORKFLOW_ENUM_TO_CLASS_MAPPING",
        new_callable=mock.PropertyMock,
    )
    def test__workflow_enum_to_class_mapping_setter_raises_type_error(
        self,
        mocked_basefactory__workflow_enum_to_class_mapping,
        new_mapping_value,
        base_factory,
    ):
        # arrange
        mocked_basefactory__workflow_enum_to_class_mapping.return_value = {}

        # act & assert
        with pytest.raises(TypeError, match="Workflow mapping must be a dict."):
            base_factory._WORKFLOW_ENUM_TO_CLASS_MAPPING = new_mapping_value

    @pytest.mark.parametrize("workflow_enum", ["ENUM_MEMBER"])
    @mock.patch.object(
        BaseFactory,
        "_BaseFactory__WORKFLOW_ENUM_TO_CLASS_MAPPING",
        new_callable=mock.PropertyMock,
    )
    def test___validate_workflow_enum(
        self,
        mocked_basefactory__workflow_enum_to_class_mapping,
        base_factory,
        workflow_enum,
    ):
        # arrange
        mocked_basefactory__workflow_enum_to_class_mapping.return_value = {
            "ENUM_MEMBER": "WORKFLOW_CLASS"
        }

        # act
        workflow_class = base_factory._BaseFactory__validate_workflow_enum(
            workflow_enum
        )
        # assert
        assert workflow_class is None

    @pytest.mark.parametrize("workflow_enum", ["ENUM_MEMBER"])
    @mock.patch.object(mock.Mock, "value", new_callable=mock.PropertyMock, create=True)
    @mock.patch.object(
        BaseFactory,
        "_WORKFLOW_ENUM_TO_CLASS_MAPPING",
        new_callable=mock.PropertyMock,
        return_value={mock.Mock: "WORKFLOW_CLASS"},
    )
    def test___validate_workflow_enum_raises_value_error(
        self,
        mocked_workflow_enum_to_class_mapping,
        mocked_enum_value,
        workflow_enum,
        base_factory,
    ):
        # arrange
        return_value = "OTHER_ENUM_MEMBER"
        mocked_enum_value.return_value = return_value

        # act & assert
        with pytest.raises(
            ValueError,
            match=f"m=__validate_workflow_class, msg=DAG Workflow {workflow_enum} does not exist, available_workflows=\['{return_value}'\]",
        ):
            _ = base_factory._BaseFactory__validate_workflow_enum(workflow_enum)
            mocked_enum_value.assert_called()
            mocked_workflow_enum_to_class_mapping.assert_called_once()

    @pytest.mark.parametrize("workflow_enum", ["ENUM_MEMBER"])
    @mock.patch.object(
        BaseFactory,
        "_BaseFactory__WORKFLOW_ENUM_TO_CLASS_MAPPING",
        new_callable=mock.PropertyMock,
    )
    def test__dispatch_workflow_class(
        self,
        mocked_basefactory__workflow_enum_to_class_mapping,
        base_factory,
        workflow_enum,
    ):
        # arrange
        mocked_basefactory__workflow_enum_to_class_mapping.return_value = {
            "ENUM_MEMBER": "WORKFLOW_CLASS"
        }
        # act
        workflow_class = base_factory._dispatch_workflow_class(workflow_enum)
        # assert
        assert workflow_class == "WORKFLOW_CLASS"
