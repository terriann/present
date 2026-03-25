/// RFC 4180 compliant CSV field escaping.
///
/// Wraps the field in double quotes if it contains a comma, double quote,
/// newline, or carriage return. Internal double quotes are doubled (`""`).
/// Fields that need no escaping are returned unchanged.
func escapeCSVField(_ field: String) -> String {
    let needsQuoting = field.contains(",")
        || field.contains("\"")
        || field.contains("\n")
        || field.contains("\r")

    guard needsQuoting else { return field }
    let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escaped)\""
}
