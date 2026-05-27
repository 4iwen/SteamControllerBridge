struct PuckState: Equatable {
    var is_present: Bool
    var vendor_id: Int?
    var product_id: Int?
    var product_name: String?
    var manufacturer: String?
    var transport: String?
    var location_id: Int?
    var is_legacy: Bool

    static let notDetected = PuckState(
        is_present: false,
        vendor_id: nil,
        product_id: nil,
        product_name: nil,
        manufacturer: nil,
        transport: nil,
        location_id: nil,
        is_legacy: false
    )
}
