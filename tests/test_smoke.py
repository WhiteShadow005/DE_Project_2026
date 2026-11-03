"""Basic smoke tests to verify repository setup and core modules."""

from src import __version__
from src.utils.config import load_config
from src.utils.logger import get_logger


def test_package_version():
    """Verify that version string is defined."""
    assert __version__ == "0.1.0"


def test_logger_initialization():
    """Verify that the custom logger initializes properly."""
    logger = get_logger("test_logger")
    assert logger is not None
    assert logger.name == "test_logger"


def test_config_loader():
    """Verify that default configuration loads without errors."""
    config = load_config()
    assert isinstance(config, dict)
    assert "app" in config
    assert config["app"]["name"] == "DE_Project_2026"
