"""Discover items from a STAC API source based on spatial and temporal filters."""
from typing import List, Optional
from pystac_client import Client

def discover_items(source_stac: str, collections: List[str], max_items: int) -> List[dict]:
    """Discover items from a STAC API source."""
    client = Client.open(source_stac)
    search = client.search(collections=collections, max_items=max_items)
    return [i.to_dict() for i in search.get_items()]

def pick_input_href(item_dict: dict) -> Optional[str]:
    """Pick a suitable input href from the item dictionary."""
    assets = item_dict.get("assets", {}) or {}
    preferred_keys = ["eopf", "zarr", "data"]
    for k in preferred_keys:
        href = assets.get(k, {}).get("href")
        if href:
            return href
    # fallback: zarr-ish media type or first available href
    for a in assets.values():
        t = (a.get("type") or "").lower()
        if "vnd+zarr" in t or "zarr" in (a.get("roles") or []):
            return a.get("href")
    for a in assets.values():
        if a.get("href"):
            return a["href"]
    return None
