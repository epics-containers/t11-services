#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyyaml"]
# ///
"""Print the IOC container image for a service, read from its values.yaml.

values.yaml may list other images too (initContainers, extraContainers,
sub-charts such as odin), so this looks for a single ioc-instance.image at
any depth (top level or nested under a sub-chart, e.g.
odin-eiger.ioc-instance.image) before falling back to the only image in the
file. If several images are found and none can be picked out this way, it
exits with an explanatory error instead of guessing.
"""

import sys

import yaml


def images(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "image" and isinstance(value, str):
                yield value
            else:
                yield from images(value)
    elif isinstance(node, list):
        for item in node:
            yield from images(item)


def ioc_images(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if (
                key == "ioc-instance"
                and isinstance(value, dict)
                and isinstance(value.get("image"), str)
            ):
                yield value["image"]
            else:
                yield from ioc_images(value)
    elif isinstance(node, list):
        for item in node:
            yield from ioc_images(item)


def main(values_path):
    with open(values_path) as f:
        values = yaml.safe_load(f) or {}
    ioc = list(ioc_images(values))
    found = list(images(values))
    if len(ioc) == 1:
        print(ioc[0])
    elif len(found) == 1:
        print(found[0])
    elif found:
        sys.exit(
            f"{values_path} lists several images {found} and no single "
            "ioc-instance.image (top level or under a sub-chart) to pick the IOC "
            "image from. Set the IOC image there, or list the service in "
            ".ci_skip_checks (which skips ALL CI checks for it, including helm lint)"
        )


if __name__ == "__main__":
    main(sys.argv[1])
