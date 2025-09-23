import Foundation

func formatTemplateJSON(_ template: TipTemplate) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(template),
          let json = String(data: data, encoding: .utf8) else {
        return "Unable to display template data"
    }
    return json
}
