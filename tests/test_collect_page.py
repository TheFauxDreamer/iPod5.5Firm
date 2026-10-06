import html
import importlib.util
import re
from pathlib import Path

RE = Path(__file__).resolve().parent.parent / "re"


def test_page_agrees_with_script():
    """The page for iPod owners has a copy of the script. Run re/build-collect-page.py after a change."""
    spec = importlib.util.spec_from_file_location("build_collect_page", RE / "build-collect-page.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    page = (RE / "collect-ipod-info.html").read_text()
    assert page == module.build(), "re/collect-ipod-info.html is out of date: run python3 re/build-collect-page.py"
    for pre_id, name in [("script", "collect-ipod-info.sh"), ("script-win", "collect-ipod-info.ps1")]:
        pre = re.search(rf'<pre id="{pre_id}">(.*?)</pre>', page, re.S).group(1)
        assert html.unescape(pre) == (RE / name).read_text()


def test_page_is_self_contained():
    page = (RE / "collect-ipod-info.html").read_text()
    assert not re.search(r'<(link|script)[^>]+(href|src)=["\']https?:', page)
    assert "@import" not in page and "url(http" not in page
