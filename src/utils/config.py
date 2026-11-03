"""Configuration loader supporting environment variables and YAML settings."""

import os
from pathlib import Path
from typing import Any, Dict

# Base project root
PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent


def load_config(config_path: str = "config/config.yaml") -> Dict[str, Any]:
    """Loads configuration dictionary from YAML file if available, falling back to defaults.

    Args:
        config_path: Relative or absolute path to the configuration file.

    Returns:
        Dictionary containing project configuration.
    """
    full_path = PROJECT_ROOT / config_path
    config: Dict[str, Any] = {
        "app": {
            "name": "DE_Project_2026",
            "version": "0.1.0",
            "environment": os.getenv("ENVIRONMENT", "development"),
        },
        "paths": {
            "raw": str(PROJECT_ROOT / "data" / "raw"),
            "staging": str(PROJECT_ROOT / "data" / "staging"),
            "warehouse": str(PROJECT_ROOT / "data" / "warehouse"),
        },
    }

    if full_path.exists():
        try:
            import yaml  # type: ignore

            with open(full_path, "r", encoding="utf-8") as f:
                loaded = yaml.safe_load(f)
                if isinstance(loaded, dict):
                    config.update(loaded)
        except ImportError:
            # PyYAML not yet installed in active environment, using fallback defaults
            pass

    return config
