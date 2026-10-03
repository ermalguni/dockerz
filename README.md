# dockerz

Docker bindings for Zig

## Docker Compose support

The Compose loader accepts a single YAML document from memory and returns
an arena-owned `LoadedProject`. The caller handles file reading and calls
`LoadedProject.deinit()` when finished.

Supported fields:

- Project: `name`, `services`, `networks`.
- Service: `image`, `command`, `environment`, `networks`.
- Network: `name`, `driver`, `internal`, `external`.
- Service network attachment: `aliases`.

Each service requires an image. Managed networks currently support only the `bridge` driver. External networks reference existing Docker networks; loading does not check their existence.

Commands accept string or list form. Environment entries and service networks accept mapping or list form. Services without explicit network attachments use the default network.

Project-name precedence is an explicit caller override, the document's `name`, then a caller-provided fallback. Directory-name discovery is not performed.

Unsupported behavior-bearing fields are rejected. Extension fields prefixed with `x-` are ignored when checking configuration fields. The obsolete top-level `version` field is accepted but has no effect.

Loading only constructs and validates the project; it does not create Docker resources.

### YAML parser limitations

The pinned YAML dependency currently rejects some valid nested flow
mappings, including `services: {web: {image: nginx}}`. Use block mappings
for Compose declarations.### Environment handling

The initial loader assumes that the caller supplies Compose content with
environment-variable interpolation already completed.

It will not automatically:

- Discover or load `.env` files.
- Read the host process environment.
- Expand `$VARIABLE` or `${VARIABLE}` expressions.

Explicit service `environment` entries are separate from Compose-file
interpolation. Empty strings and entries without values must remain
distinct; entries without values do not cause the loader to consult the
host environment.

Automatic `.env` discovery and Compose-compatible environment resolution
are planned for a later implementation.
