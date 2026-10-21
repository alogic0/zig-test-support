//! Native acceptance mechanisms; scenarios and process-wide policy stay in callers.
pub const compiled_mode = @import("builtin").mode;
pub const process = @import("process");
pub const command = @import("command.zig");
pub const readiness = @import("readiness.zig");
pub const Workspace = @import("workspace.zig");
pub const files = @import("files.zig");
pub const json = @import("json.zig");
pub const png = @import("png.zig");
pub const resources = @import("resources.zig");
pub const Diagnostic = @import("diagnostic.zig").Diagnostic;
