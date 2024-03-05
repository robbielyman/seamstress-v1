/// the module interface allows seamstress to be agnostic about what it runs
/// it's my hope that it will allow for more flexible extensibility
const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const Cleanup = Seamstress.Cleanup;
const Spindle = @import("spindle.zig");
const Module = @This();

// these self pointers end up having to be on the heap, which is a little annoying
self: ?*anyopaque = null,
vtable: *const VTable,

const VTable = struct {
    init_fn: *const fn (*Module, *Spindle) Error!void,
    deinit_fn: *const fn (*const Module, *Spindle, Cleanup) void,
    launch_fn: *const fn (*const Module, *Spindle) Error!void,
};

// m is not const because we assign to self here
// only fatal errors of type Error should be reported
pub fn init(m: *Module, vm: *Spindle) Error!void {
    try m.vtable.init_fn(m, vm);
}

// m is const because the thing we care about is self, which is already a pointer
pub fn deinit(m: *const Module, vm: *Spindle, cleanup: Cleanup) void {
    m.vtable.deinit_fn(m, vm, cleanup);
}

// m is const because the thing we care about is self, which is already a pointer
// only fatal errors of type Error should be reported
pub fn launch(m: *const Module, vm: *Spindle) Error!void {
    try m.vtable.launch_fn(m, vm);
}
