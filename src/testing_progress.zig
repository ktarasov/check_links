const TestingProgress = @This();

pub fn start(node: TestingProgress, name: []const u8, estimated_total_items: usize) TestingProgress {
    _ = node;
    _ = name;
    _ = estimated_total_items;
    return .{};
}

pub fn end(node: TestingProgress) void {
    _ = node;
}

pub fn setName(node: TestingProgress, name: []const u8) void {
    _ = node;
    _ = name;
}

pub fn completeOne(node: TestingProgress) void {
    _ = node;
}
