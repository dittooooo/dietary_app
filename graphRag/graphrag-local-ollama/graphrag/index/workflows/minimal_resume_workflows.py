# Copyright (c) 2024 Microsoft Corporation.
# Licensed under the MIT License

"""Minimal workflow set for resuming from merged artifacts."""

from .typing import WorkflowDefinitions
from .v1.create_final_entities import (
    build_steps as build_create_final_entities_steps,
    workflow_name as create_final_entities,
)
from .v1.create_final_nodes import (
    build_steps as build_create_final_nodes_steps,
    workflow_name as create_final_nodes,
)
from .v1.create_final_relationships import (
    build_steps as build_create_final_relationships_steps,
    workflow_name as create_final_relationships,
)
from .v1.create_final_communities import (
    build_steps as build_create_final_communities_steps,
    workflow_name as create_final_communities,
)
from .v1.create_final_community_reports import (
    build_steps as build_create_final_community_reports_steps,
    workflow_name as create_final_community_reports,
)

default_workflows: WorkflowDefinitions = {
    create_final_entities: build_create_final_entities_steps,
    create_final_nodes: build_create_final_nodes_steps,
    create_final_relationships: build_create_final_relationships_steps,
    create_final_communities: build_create_final_communities_steps,
    create_final_community_reports: build_create_final_community_reports_steps,
}
