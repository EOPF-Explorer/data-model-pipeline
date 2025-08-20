"""eopf_geozarr_pipeline.workflow.register --- Register GeoZarr items in a STAC catalog."""
from datetime import datetime
from pathlib import Path

import pystac
from pystac import Asset, Catalog, CatalogType, Collection, Item


def ensure_catalog(root_dir: Path) -> Catalog:
    """Ensure the STAC catalog exists."""
    root_dir.mkdir(parents=True, exist_ok=True)
    cat_path = root_dir / "catalog.json"
    if cat_path.exists():
        return Catalog.from_file(str(cat_path))
    cat = Catalog(id="geozarr-catalog", description="Local GeoZarr target catalog")
    cat.normalize_hrefs(str(root_dir))
    cat.save(catalog_type=CatalogType.RELATIVE_PUBLISHED)
    return cat

def ensure_collection(cat: Catalog, coll_id: str) -> Collection:
    """Ensure a collection exists in the catalog."""
    for c in cat.get_all_collections():
        if c.id == coll_id:
            return c
    extent = pystac.Extent(
        spatial=pystac.SpatialExtent([[-180, -90, 180, 90]]),
        temporal=pystac.TemporalExtent([[None, None]]),
    )
    coll = Collection(id=coll_id, description=f"GeoZarr outputs for {coll_id}", extent=extent, license="proprietary")
    cat.add_child(coll)
    return coll

def dict_to_item(source_item: dict, target_collection_id: str) -> Item:
    """Convert a source item dictionary to a target Item."""
    item = Item.from_dict(source_item, preserve_dict=True)
    item.collection_id = target_collection_id
    item.assets = {}  # clear, we’ll add GeoZarr
    # processing metadata
    item.properties["processing:datetime"] = datetime.utcnow().isoformat() + "Z"
    item.properties.setdefault("processing:software", {})["eopf-geozarr"] = ">=0.1.0"
    return item

def add_geozarr_asset(item: Item, href: str):
    """Add a GeoZarr asset to the item."""
    asset = Asset(
        href=href,
        media_type="application/vnd+zarr",
        roles=["data"],
        title="GeoZarr (WOZ) dataset",
    )
    item.add_asset("geozarr", asset)

def save_catalog(cat: Catalog, root_dir: Path):
    """Save the catalog to the specified root directory."""
    cat.normalize_hrefs(str(root_dir))
    cat.save(catalog_type=CatalogType.RELATIVE_PUBLISHED)
