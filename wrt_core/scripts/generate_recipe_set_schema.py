#!/usr/bin/env python3
import json
import glob
import os
import sys

def generate_schema():
    core_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    recipes_dir = os.path.join(core_dir, "recipes")
    schema_path = os.path.join(core_dir, "recipe_sets", "recipe_set.schema.json")

    recipe_names = []
    for recipe_json in glob.glob(os.path.join(recipes_dir, "*", "recipe.json")):
        recipe_name = os.path.basename(os.path.dirname(recipe_json))
        recipe_names.append(recipe_name)

    recipe_names.sort()

    schema = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "title": "RecipeSet",
        "description": "JSON Schema for wrt_relese Recipe Set presets with auto-completed recipe enum values",
        "type": "object",
        "required": ["name", "recipes"],
        "properties": {
            "$schema": {
                "type": "string"
            },
            "name": {
                "type": "string",
                "description": "Unique identifier of the recipe set"
            },
            "description": {
                "type": "string",
                "description": "Detailed description of what this recipe set includes"
            },
            "recipes": {
                "type": "array",
                "description": "List of recipes enabled in this preset",
                "items": {
                    "type": "string",
                    "enum": recipe_names
                },
                "uniqueItems": True
            },
            "disable_recipes": {
                "type": "array",
                "description": "List of recipes explicitly disabled in this preset",
                "items": {
                    "type": "string",
                    "enum": recipe_names
                },
                "uniqueItems": True
            }
        },
        "additionalProperties": False
    }

    with open(schema_path, "w", encoding="utf-8") as f:
        json.dump(schema, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"[+] Successfully generated JSON Schema with {len(recipe_names)} recipe enum values at:")
    print(f"    {schema_path}")

if __name__ == "__main__":
    generate_schema()
