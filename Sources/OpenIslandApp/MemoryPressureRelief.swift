import Darwin

enum MemoryPressureRelief {
    static func releaseEmptyMallocPages() {
        _ = malloc_zone_pressure_relief(nil, 0)
    }
}
