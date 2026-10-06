# dockerz

Docker bindings for Zig

## Docker Compose support

The Compose loader accepts a single YAML document from memory and returns an arena-owned `LoadedProject`. The caller handles file reading and calls `LoadedProject.deinit()` when finished.

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

The pinned YAML dependency currently rejects some valid nested flow mappings, including `services: {web: {image: nginx}}`. Use block mappings for Compose declarations.### Environment handling

The initial loader assumes that the caller supplies Compose content with environment-variable interpolation already completed.

It will not automatically:

- Discover or load `.env` files.
- Read the host process environment.
- Expand `$VARIABLE` or `${VARIABLE}` expressions.

Explicit service `environment` entries are separate from Compose-file interpolation. Empty strings and entries without values must remain distinct; entries without values do not cause the loader to consult the host environment.

Automatic `.env` discovery and Compose-compatible environment resolution are planned for a later implementation.

### Engine errors, restart deadlines, and TLS

Unexpected HTTP responses preserve their status and decoded Docker JSON message in `client.last_error`. Existing Zig status errors remain unchanged. `details_error` records failure to read or decode the error message.

Diagnostics belong to the client and expire at the start of the next `Client.request()` or when the client is deinitialized. Inspect them immediately in `catch`; do not overlap requests on one client.

`RestartOptions.timeout_seconds` controls Docker's stop grace period. `RestartOptions.timeout` independently controls the HTTP deadline and defaults to `.none`, matching stop operations.

TCP transport uses HTTP when `tls` is null and HTTPS when it is configured. An empty TLS configuration uses system CA trust. Custom CAs and mutual-TLS client certificates are supported. TLS paths and directory handles are borrowed and must remain valid for the client's lifetime.

With the pinned TLS dependency, use a DNS hostname matching the server certificate. An IP-SAN-only connection was observed to fail hostname validation. Server verification remains enabled by default.

## Public API

The library exposes two feature namespaces:

- `dockerz.engine`: Docker client, configuration, API models, version information, and resource-specific APIs.
- `dockerz.compose`: project loading, project models, execution options, the executor, and execution reports.

Connect an Engine client before passing it to `compose.Executor`. The executor borrows the client; the caller retains ownership.

`Executor.up()` and `Executor.down()` return reports. Inspect `failure` and `cleanup_errors.items`, then call `Report.deinit()`. Deinitializing a report releases memory only; explicit `down()` performs project teardown.

Implementation directories are not part of the supported public API. The old top-level Client and executor namespaces have been removed.

Following is an example to use the API:

```zig
const std = @import("std");
const dockerz = @import("dockerz");

const engine = dockerz.engine;
const compose = dockerz.compose;

pub fn startProject(
   allocator: std.mem.Allocator,
   client: *engine.Client,
   yaml: []const u8,
) !void {
   var loaded = try compose.load(
       allocator,
       yaml,
       .{ .name = "demo" },
   );
   defer loaded.deinit();

   const executor: compose.Executor = .{
       .client = client,
   };

   var report = executor.up(loaded.value, .{});
   defer report.deinit();

   try checkReport(&report);
}

pub fn removeProject(
   client: *engine.Client,
   project_name: []const u8,
) !void {
   const executor: compose.Executor = .{
       .client = client,
   };

   var report = executor.down(project_name, .{
       .stop = .{ .timeout_signal = 10 },
   });
   defer report.deinit();

   try checkReport(&report);
}

fn checkReport(report: *const compose.Report) !void {
   for (report.cleanup_errors.items) |issue| {
       std.debug.print(
           "{s} {s} {s}: {s}\n",
           .{
               @tagName(issue.kind),
               issue.id,
               @tagName(issue.operation),
               @errorName(issue.err),
           },
       );
   }

   if (report.failure) |err| return err;
}
```
