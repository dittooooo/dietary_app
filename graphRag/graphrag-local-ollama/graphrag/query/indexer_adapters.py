from typing import cast
import logging
import pandas as pd

from graphrag.model import (
    Community,
    CommunityReport,
    Covariate,
    Entity,
    Relationship,
    TextUnit,
)
from graphrag.query.input.loaders.dfs import (
    read_communities,
    read_community_reports,
    read_covariates,
    read_entities,
    read_relationships,
    read_text_units,
)

log = logging.getLogger(__name__)


def read_indexer_text_units(final_text_units: pd.DataFrame) -> list[TextUnit]:
    """Read in the Text Units from the raw indexing outputs."""
    return read_text_units(
        df=final_text_units,
        short_id_col=None,
        covariates_col=None,
    )


def read_indexer_covariates(final_covariates: pd.DataFrame) -> list[Covariate]:
    """Read in the Covariates from the raw indexing outputs."""
    covariate_df = final_covariates.copy()
    covariate_df["id"] = covariate_df["id"].astype(str)
    return read_covariates(
        df=covariate_df,
        short_id_col="human_readable_id",
        attributes_cols=[
            "object_id",
            "status",
            "start_date",
            "end_date",
            "description",
        ],
        text_unit_ids_col=None,
    )


def read_indexer_relationships(final_relationships: pd.DataFrame) -> list[Relationship]:
    """Read in the Relationships from the raw indexing outputs."""
    return read_relationships(
        df=final_relationships,
        short_id_col="human_readable_id",
        description_embedding_col=None,
        document_ids_col=None,
        attributes_cols=["rank"],
    )


def read_indexer_reports(
    final_community_reports: pd.DataFrame,
    final_nodes: pd.DataFrame,
    community_level: int,
) -> list[CommunityReport]:
    """Read in the Community Reports from the raw indexing outputs."""
    report_df = final_community_reports.copy()
    node_df = _filter_under_community_level(final_nodes, community_level)
    node_df["community"] = node_df["community"].fillna(-1).astype(int)

    # select max level per title
    summary_df = (
        node_df.groupby(["title"]).agg({"community": "max"}).reset_index()
    )
    summary_df["community"] = summary_df["community"].astype(str)
    filtered = summary_df["community"].drop_duplicates()

    report_df = _filter_under_community_level(report_df, community_level)
    report_df = report_df.merge(filtered, on="community", how="inner")

    return read_community_reports(
        df=report_df,
        id_col="community",
        short_id_col="community",
        summary_embedding_col=None,
        content_embedding_col=None,
    )


def read_indexer_entities(
    final_nodes: pd.DataFrame,
    final_entities: pd.DataFrame,
    community_level: int,
) -> list[Entity]:
    """Read in the Entities from the raw indexing outputs."""
    node_df = _filter_under_community_level(final_nodes, community_level)
    node_df = cast(
        pd.DataFrame,
        node_df[["title", "degree", "community"]]
        .rename(columns={"title": "name", "degree": "rank"}),
    )

    node_df["community"] = node_df["community"].fillna(-1).astype(int)
    node_df["rank"] = node_df["rank"].astype(int)

    # for duplicate entities, keep highest community
    grouped = (
        node_df.groupby(["name", "rank"]).agg({"community": "max"}).reset_index()
    )
    grouped["community"] = grouped["community"].apply(lambda x: [str(x)])

    final_df = (
        grouped.merge(final_entities, on="name", how="inner").drop_duplicates(subset=["name"])
    )

    return read_entities(
        df=final_df,
        id_col="id",
        title_col="name",
        type_col="type",
        short_id_col="human_readable_id",
        description_col="description",
        community_col="community",
        rank_col="rank",
        name_embedding_col=None,
        description_embedding_col="description_embedding",
        graph_embedding_col=None,
        text_unit_ids_col="text_unit_ids",
        document_ids_col=None,
    )


# def read_indexer_communities(
#     final_communities: pd.DataFrame,
#     final_community_reports: pd.DataFrame,
# ) -> list[Community]:
#     """Read in the Communities from the raw indexing outputs.

#     Reconstruct the community hierarchy information and attach sub-communities."""
#     communities_df = final_communities.copy()
#     exploded = communities_df.explode("entity_ids")
#     reports = final_community_reports

#     # ensure matching communities and reports
#     missing = communities_df[~communities_df["community"].isin(reports["community"].unique())]["community"].tolist()
#     if missing:
#         log.warning("Missing reports for communities: %s", missing)
#         communities_df = communities_df[communities_df["community"].isin(reports["community"].unique())]
#         exploded = exploded[exploded["community"].isin(reports["community"].unique())]

#     return read_communities(
#         communities_df,
#         id_col="id",
#         short_id_col="community",
#         title_col="title",
#         level_col="level",
#         entities_col=None,
#         relationships_col=None,
#         covariates_col=None,
#         parent_col="parent",
#         children_col="children",
#         attributes_cols=None,
#     )

def read_indexer_communities(
    final_communities: pd.DataFrame,
    final_nodes: pd.DataFrame,
    final_community_reports: pd.DataFrame,
) -> list[Community]:
    """Read in the Communities from the raw indexing outputs.

    Reconstruct the community hierarchy information and add to the sub-community field.
    """
    
    # DEBUG: 查看 final_communities 的結構
    print("=== final_communities.head() ===")
    print(final_communities.head())
    print("=== final_communities.columns ===")
    print(final_communities.columns.tolist())
        
    communities_df = final_communities
    nodes_df = final_nodes
    reports_df = final_community_reports
    
    # 修正缺少 'community' 欄位問題
    communities_df["community"] = communities_df["raw_community"]

    # ensure communities matches community reports
    missing_reports = communities_df[
        ~communities_df.raw_community.isin(reports_df.community.unique())
    ].raw_community.to_list()
    if len(missing_reports):
        log.warning("Missing reports for communities: %s", missing_reports)
        communities_df = communities_df.loc[
            communities_df.community.isin(reports_df.community.unique())
        ]
        nodes_df = nodes_df.loc[nodes_df.community.isin(reports_df.community.unique())]
    
    # from graphrag.index.operations.summarize_communities import restore_community_hierarchy
    # # reconstruct the community hierarchy
    # # note that restore_community_hierarchy only return communities with sub communities
    # community_hierarchy = restore_community_hierarchy(input=nodes_df)

    # # small datasets can result in hierarchies that are only one deep, so the hierarchy will have no rows
    # if not community_hierarchy.empty:
    #     community_hierarchy = (
    #         community_hierarchy.groupby(["community"])
    #         .agg({"sub_community": list})
    #         .reset_index()
    #         .rename(columns={"sub_community": "sub_community_ids"})
    #     )
    #     # add sub community IDs to community DataFrame
    #     communities_df = communities_df.merge(
    #         community_hierarchy, on="community", how="left"
    #         # community_hierarchy, how="left"
    #     )
    #     # replace NaN sub community IDs with empty list
    #     communities_df.sub_community_ids = communities_df.sub_community_ids.apply(
    #         lambda x: x if isinstance(x, list) else []
    #     )

    return read_communities(
        communities_df,
        id_col="id",
        short_id_col="community",
        title_col="title",
        level_col="level",
        entities_col=None,
        relationships_col=None,
        covariates_col=None,
        sub_communities_col="sub_community_ids",
        attributes_cols=None,
    )


def _filter_under_community_level(df: pd.DataFrame, community_level: int) -> pd.DataFrame:
    return cast(pd.DataFrame, df[df.level <= community_level])
