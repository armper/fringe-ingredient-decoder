#!/usr/bin/env python3

import csv
import io
import json
import re
import unicodedata
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path


ROOT = Path("/Users/alperea/ios-apps/fringe-ingredient-decoder")
OUTPUT_PATH = ROOT / "FringeIngredientDecoder" / "IngredientCatalog.json"

OFF_FOOD_INGREDIENTS_URL = (
    "https://raw.githubusercontent.com/openfoodfacts/openfoodfacts-server/main/taxonomies/food/ingredients.txt"
)
OFF_ADDITIVES_URL = (
    "https://raw.githubusercontent.com/openfoodfacts/openfoodfacts-server/main/taxonomies/additives.txt"
)
OFF_BEAUTY_INGREDIENTS_URL = (
    "https://raw.githubusercontent.com/openfoodfacts/openfoodfacts-server/main/taxonomies/beauty/ingredients-cosing-obf.txt"
)
FDA_IIG_URL = "https://www.fda.gov/media/190589/download?attachment"


PURPOSE_BY_CATEGORY = {
    "additive": "It likely supports taste, tartness, texture, or shelf stability.",
    "preservative": "It likely helps the product last longer and stay stable.",
    "sweetener": "It likely adds sweetness or rounds out flavor.",
    "coloring": "It changes or standardizes the product's appearance.",
    "emulsifier": "It helps ingredients stay mixed instead of separating.",
    "stabilizer": "It helps control texture and keep the formula uniform.",
    "fragrance": "It shapes the scent of the product.",
    "solvent": "It helps dissolve or spread other ingredients.",
    "surfactant": "It helps water mix with oils and lift residue.",
    "unknown": "It appears on ingredient labels, but its role can vary by formula.",
}

ADDITIVE_CLASS_MAP = {
    "acidity-regulator": "additive",
    "acid": "additive",
    "acidifier": "additive",
    "anti-caking-agent": "additive",
    "anti-foaming-agent": "additive",
    "antioxidant": "additive",
    "bulking-agent": "stabilizer",
    "carrier": "additive",
    "colour": "coloring",
    "color": "coloring",
    "colour-retention-agent": "additive",
    "emulsifier": "emulsifier",
    "firming-agent": "stabilizer",
    "flavour-enhancer": "additive",
    "flour-treatment-agent": "additive",
    "foaming-agent": "additive",
    "gelling-agent": "stabilizer",
    "glazing-agent": "additive",
    "humectant": "additive",
    "modified-starch": "stabilizer",
    "packing-gas": "additive",
    "preservative": "preservative",
    "propellant": "additive",
    "raising-agent": "additive",
    "sequestrant": "additive",
    "stabiliser": "stabilizer",
    "stabilizer": "stabilizer",
    "sweetener": "sweetener",
    "thickener": "stabilizer",
}

INCI_FUNCTION_MAP = {
    "antimicrobial": "preservative",
    "antiseborrhoeic": "preservative",
    "antistatic": "stabilizer",
    "cleansing": "surfactant",
    "deodorant": "fragrance",
    "detergent": "surfactant",
    "emulsifying": "emulsifier",
    "film-forming": "stabilizer",
    "foaming": "surfactant",
    "gelling": "stabilizer",
    "masking": "fragrance",
    "opacifying": "stabilizer",
    "perfuming": "fragrance",
    "plasticiser": "stabilizer",
    "plasticizer": "stabilizer",
    "preservative": "preservative",
    "solvent": "solvent",
    "surface-modifying": "surfactant",
    "surfactant": "surfactant",
    "viscosity-controlling": "stabilizer",
}


@dataclass
class CatalogEntry:
    name: str
    category: str
    what_it_is: str
    purpose: str


def fetch_text(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": "FringeIngredientDecoder/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8", "ignore")


def fetch_bytes(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "FringeIngredientDecoder/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def normalize(text: str) -> str:
    folded = unicodedata.normalize("NFKD", text)
    folded = "".join(character for character in folded if not unicodedata.combining(character))
    folded = folded.lower()
    folded = folded.replace("&", " and ")
    folded = re.sub(r"(?i)\borganic\b", " ", folded)
    folded = re.sub(r"(?i)\band/or\b", " ", folded)
    folded = re.sub(r"[\u00ae\u2122*]", " ", folded)
    folded = re.sub(r"[.]+", " ", folded)
    folded = re.sub(r"\s*/\s*", "/", folded)
    folded = re.sub(r"\s*-\s*", "-", folded)
    folded = re.sub(r"[^a-z0-9/+\- ]+", " ", folded)
    folded = re.sub(r"\s+", " ", folded)
    return folded.strip(" -/")


def title_case_name(text: str) -> str:
    parts = re.split(r"(\s+)", text.strip())
    output = []
    for part in parts:
        if not part or part.isspace():
            output.append(part)
            continue
        if len(part) <= 3 and any(character.isalpha() for character in part):
            output.append(part.upper())
        else:
            output.append(part[:1].upper() + part[1:].lower())
    return "".join(output)


def compact_sentence(text: str, limit: int = 140) -> str:
    cleaned = re.sub(r"\s+", " ", text.replace("\n", " ")).strip()
    if not cleaned:
        return ""
    sentence = re.split(r"(?<=[.!?])\s+", cleaned)[0].strip()
    if len(sentence) <= limit:
        return sentence
    shortened = sentence[: limit - 1].rsplit(" ", 1)[0].strip()
    return (shortened or sentence[: limit - 1]).rstrip(",;:") + "…"


def generic_what_it_is(name: str, category: str, source: str) -> str:
    if source == "fda":
        return "An ingredient name listed in FDA's inactive ingredients database."
    if category == "fragrance":
        return "A scent ingredient or fragrance blend."
    if category == "surfactant":
        return "A cleansing or surface-active ingredient."
    if category == "solvent":
        return "A carrier ingredient used to dissolve or spread a formula."
    if category == "emulsifier":
        return "An ingredient used to keep formulas evenly mixed."
    if category == "stabilizer":
        return "An ingredient used to support texture or consistency."
    if category == "preservative":
        return "An ingredient used to help preserve the formula."
    if category == "sweetener":
        return "A sweetener used in food and drink labels."
    if category == "coloring":
        return "A color additive used on ingredient labels."
    if category == "additive":
        return "A functional additive used in packaged formulas."
    return f"A named ingredient found in the {source.upper()} ingredient data."


def add_entry(entries, aliases, canonical_name, alias_names, category, description, purpose, source):
    canonical_key = normalize(canonical_name)
    if not canonical_key:
        return

    what_it_is = compact_sentence(description) or generic_what_it_is(canonical_name, category, source)
    entry = CatalogEntry(
        name=title_case_name(canonical_name),
        category=category,
        what_it_is=what_it_is,
        purpose=(purpose or PURPOSE_BY_CATEGORY[category]),
    )

    if canonical_key not in entries:
        entries[canonical_key] = entry

    alias_pool = [canonical_name] + list(alias_names)
    for alias in alias_pool:
        normalized_alias = normalize(alias)
        if normalized_alias:
            aliases.setdefault(normalized_alias, canonical_key)
            aliases.setdefault(normalized_alias.replace("-", " "), canonical_key)


def parse_blocks(text: str):
    block = []
    for line in text.splitlines():
        if line.strip():
            block.append(line.rstrip())
            continue
        if block:
            yield block
            block = []
    if block:
        yield block


def parse_taxonomy_block(block):
    names_by_lang = {}
    properties = {}
    standalone_synonyms = []

    for raw_line in block:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        property_match = re.match(r"^([a-z_]+(?:_[a-z]+)?):([a-z_]+):\s*(.*)$", line)
        if property_match:
            key, lang, value = property_match.groups()
            values = [part.strip() for part in value.split(",") if part.strip()]
            if key == "synonyms":
                if not names_by_lang:
                    if lang == "en":
                        standalone_synonyms.extend(values)
                else:
                    names_by_lang.setdefault(lang, []).extend(values)
            else:
                properties[f"{key}:{lang}"] = value.strip()
            continue

        name_match = re.match(r"^([a-z_]+):\s*(.*)$", line)
        if not name_match:
            continue

        lang, value = name_match.groups()
        if lang == "synonyms":
            continue

        values = [part.strip() for part in value.split(",") if part.strip()]
        if lang in {"en", "xx"} or len(lang) == 2 or "_" in lang:
            names_by_lang.setdefault(lang, []).extend(values)

    return names_by_lang, properties, standalone_synonyms


def build_global_synonym_aliases(aliases, synonym_groups):
    for group in synonym_groups:
        normalized = [normalize(item) for item in group if normalize(item)]
        if len(normalized) < 2:
            continue
        target = normalized[0]
        for item in normalized:
            aliases.setdefault(item, target)


def parse_off_food(entries, aliases):
    text = fetch_text(OFF_FOOD_INGREDIENTS_URL)
    synonym_groups = []

    for block in parse_blocks(text):
        names_by_lang, properties, standalone_synonyms = parse_taxonomy_block(block)
        if standalone_synonyms:
            synonym_groups.append(standalone_synonyms)
            continue

        english_names = names_by_lang.get("en", [])
        if not english_names:
            continue

        canonical = english_names[0]
        description = properties.get("description:en", "")
        add_entry(
            entries,
            aliases,
            canonical_name=canonical,
            alias_names=english_names[1:],
            category="unknown",
            description=description,
            purpose=PURPOSE_BY_CATEGORY["unknown"],
            source="off",
        )

    build_global_synonym_aliases(aliases, synonym_groups)


def category_from_additive_classes(raw_value):
    classes = []
    for token in raw_value.split(","):
        token = token.strip()
        if ":" in token:
            token = token.split(":", 1)[1]
        token = normalize(token).replace(" ", "-")
        if token:
            classes.append(token)
    for additive_class in classes:
        if additive_class in ADDITIVE_CLASS_MAP:
            return ADDITIVE_CLASS_MAP[additive_class]
    return "additive"


def parse_off_additives(entries, aliases):
    text = fetch_text(OFF_ADDITIVES_URL)
    synonym_groups = []

    for block in parse_blocks(text):
        names_by_lang, properties, standalone_synonyms = parse_taxonomy_block(block)
        if standalone_synonyms:
            synonym_groups.append(standalone_synonyms)
            continue

        english_names = names_by_lang.get("en", [])
        if not english_names:
            continue

        category = category_from_additive_classes(properties.get("additives_classes:en", ""))
        description = properties.get("description:en", "")

        preferred = None
        for name in english_names:
            if not re.fullmatch(r"e ?\d+[a-z]?", normalize(name)):
                preferred = name
                break
        canonical = preferred or english_names[0]

        add_entry(
            entries,
            aliases,
            canonical_name=canonical,
            alias_names=english_names,
            category=category,
            description=description,
            purpose=PURPOSE_BY_CATEGORY[category],
            source="off",
        )

    build_global_synonym_aliases(aliases, synonym_groups)


def category_from_inci_functions(raw_value):
    functions = []
    for token in raw_value.split(","):
        token = token.strip()
        if ":" in token:
            token = token.split(":", 1)[1]
        normalized = normalize(token).replace(" ", "-")
        if normalized:
            functions.append(normalized)

    for function in functions:
        if function in INCI_FUNCTION_MAP:
            return INCI_FUNCTION_MAP[function]
    return "unknown"


def purpose_from_inci_functions(raw_value, category):
    normalized = normalize(raw_value)
    if "skin-conditioning" in normalized or "hair-conditioning" in normalized:
        return "It helps condition, soften, or support the feel of the formula."
    if "emollient" in normalized:
        return "It helps soften the feel of the product on skin or hair."
    return PURPOSE_BY_CATEGORY[category]


def parse_off_beauty(entries, aliases):
    text = fetch_text(OFF_BEAUTY_INGREDIENTS_URL)
    synonym_groups = []

    for block in parse_blocks(text):
        names_by_lang, properties, standalone_synonyms = parse_taxonomy_block(block)
        if standalone_synonyms:
            synonym_groups.append(standalone_synonyms)
            continue

        english_names = names_by_lang.get("en", [])
        if not english_names:
            continue

        canonical = english_names[0]
        functions = properties.get("inci_functions:en", "")
        category = category_from_inci_functions(functions)
        description = properties.get("inci_description:en", "")
        purpose = purpose_from_inci_functions(functions, category)

        add_entry(
            entries,
            aliases,
            canonical_name=canonical,
            alias_names=english_names[1:],
            category=category,
            description=description,
            purpose=purpose,
            source="obf",
        )

    build_global_synonym_aliases(aliases, synonym_groups)


def parse_fda_iig(entries, aliases):
    archive = zipfile.ZipFile(io.BytesIO(fetch_bytes(FDA_IIG_URL)))
    csv_name = next(name for name in archive.namelist() if name.endswith(".csv") and name.startswith("IIR_"))
    with archive.open(csv_name) as file_handle:
        decoded = io.TextIOWrapper(file_handle, encoding="utf-8-sig", newline="")
        reader = csv.DictReader(decoded)
        seen = set()
        for row in reader:
            raw_name = (row.get("INGREDIENT_NAME") or "").strip()
            if not raw_name:
                continue
            normalized = normalize(raw_name)
            if not normalized or normalized in seen:
                continue
            if normalized in aliases or normalized in entries:
                continue
            seen.add(normalized)

            category = "unknown"
            if any(keyword in normalized for keyword in ("fragrance", "parfum", "perfume")):
                category = "fragrance"
            elif any(keyword in normalized for keyword in ("sulfate", "betaine", "glucoside")):
                category = "surfactant"
            elif any(keyword in normalized for keyword in ("glycol", "alcohol", "isododecane")):
                category = "solvent"
            elif any(keyword in normalized for keyword in ("ceteareth", "polysorbate", "lecithin", "stearate")):
                category = "emulsifier"
            elif any(keyword in normalized for keyword in ("phenoxyethanol", "benzoate", "sorbate", "tocopherol")):
                category = "preservative"

            add_entry(
                entries,
                aliases,
                canonical_name=raw_name,
                alias_names=[],
                category=category,
                description="",
                purpose=PURPOSE_BY_CATEGORY[category],
                source="fda",
            )


def main():
    entries = {}
    aliases = {}

    parse_off_food(entries, aliases)
    parse_off_additives(entries, aliases)
    parse_off_beauty(entries, aliases)
    parse_fda_iig(entries, aliases)

    payload = {
        "metadata": {
            "sources": [
                OFF_FOOD_INGREDIENTS_URL,
                OFF_ADDITIVES_URL,
                OFF_BEAUTY_INGREDIENTS_URL,
                FDA_IIG_URL,
            ]
        },
        "aliases": aliases,
        "entries": {
            key: {
                "name": value.name,
                "category": value.category,
                "whatItIs": value.what_it_is,
                "purpose": value.purpose,
            }
            for key, value in sorted(entries.items())
        },
    }

    OUTPUT_PATH.write_text(
        json.dumps(payload, separators=(",", ":"), ensure_ascii=False),
        encoding="utf-8",
    )
    print(f"Wrote {len(entries)} entries and {len(aliases)} aliases to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
