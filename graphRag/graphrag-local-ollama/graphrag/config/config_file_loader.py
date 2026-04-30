# graphrag/config/config_file_loader.py

# Copyright (c) 2024 Microsoft Corporation.
# Licensed under the MIT License

"""Load a GraphRagConfiguration from a file, using your customized create_graphrag_config."""

import json
from abc import ABC, abstractmethod
from pathlib import Path

import yaml

from graphrag.config.create_graphrag_config import create_graphrag_config  # 你的修改版
from graphrag.config.models.graph_rag_config import GraphRagConfig

# 依序搜尋的預設設定檔名稱
_default_config_files = ["settings.yaml", "settings.yml", "settings.json"]


def search_for_config_in_root_dir(root: str | Path) -> Path | None:
    """從根目錄搜尋 settings.yaml/.yml/.json，回傳第一個找到的路徑或 None。"""
    root = Path(root)
    if not root.is_dir():
        raise FileNotFoundError(f"Invalid config path: {root} is not a directory")
    for fname in _default_config_files:
        p = root / fname
        if p.is_file():
            return p
    return None


class ConfigFileLoader(ABC):
    """載入設定檔的抽象基底。"""

    @abstractmethod
    def load_config(self, config_path: str | Path) -> GraphRagConfig:
        raise NotImplementedError


class ConfigYamlLoader(ConfigFileLoader):
    """從 YAML 檔載入設定。"""

    def load_config(self, config_path: str | Path) -> GraphRagConfig:
        config_path = Path(config_path)
        if config_path.suffix not in (".yaml", ".yml"):
            raise ValueError(f"Invalid file extension for yaml: {config_path}")
        if not config_path.is_file():
            raise FileNotFoundError(f"Config file not found: {config_path}")
        # 讀 YAML，轉成 dict 並呼叫你的 create_graphrag_config
        data = yaml.safe_load(config_path.read_text(encoding="utf-8"))
        return create_graphrag_config(data, str(config_path.parent))


class ConfigJsonLoader(ConfigFileLoader):
    """從 JSON 檔載入設定。"""

    def load_config(self, config_path: str | Path) -> GraphRagConfig:
        config_path = Path(config_path)
        if config_path.suffix != ".json":
            raise ValueError(f"Invalid file extension for json: {config_path}")
        if not config_path.is_file():
            raise FileNotFoundError(f"Config file not found: {config_path}")
        data = json.loads(config_path.read_text(encoding="utf-8"))
        return create_graphrag_config(data, str(config_path.parent))


def get_config_file_loader(config_path: str | Path) -> ConfigFileLoader:
    """根據副檔名回傳對應的 Loader。"""
    ext = Path(config_path).suffix.lower()
    if ext in (".yaml", ".yml"):
        return ConfigYamlLoader()
    if ext == ".json":
        return ConfigJsonLoader()
    raise ValueError(f"Unsupported config file extension: {ext}")


def load_config_from_file(config_path: str | Path) -> GraphRagConfig:
    """一行呼叫：自動選 Loader 並載入設定，回傳 GraphRagConfig。"""
    loader = get_config_file_loader(config_path)
    return loader.load_config(config_path)
