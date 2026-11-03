"""Main application entry point for DE_Project_2026."""

import sys
from src.utils.logger import get_logger
from src.utils.config import load_config

logger = get_logger("DE_Project_2026.Main")


def main() -> int:
    """Initializes project configuration and displays pipeline readiness."""
    logger.info("Initializing DE_Project_2026...")
    config = load_config()

    app_name = config.get("app", {}).get("name", "DE_Project_2026")
    env = config.get("app", {}).get("environment", "development")

    logger.info(f"Loaded configuration for '{app_name}' (Environment: {env})")
    logger.info("Repository setup is complete and ready for pipeline development.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
