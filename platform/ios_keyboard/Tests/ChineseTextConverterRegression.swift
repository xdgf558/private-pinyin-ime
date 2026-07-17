import Foundation

private struct ConversionCase {
    let source: String
    let expected: String
}

private func expectEqual(_ actual: String, _ expected: String, source: String) {
    guard actual == expected else {
        fatalError("Traditional conversion mismatch for \(source): \(actual) != \(expected)")
    }
}

private let phraseCases = [
    ConversionCase(source: "里面头发发展干嘛面条", expected: "裡面頭髮發展乾嘛麵條"),
    ConversionCase(source: "皇后在后面", expected: "皇后在後面"),
    ConversionCase(source: "只有一只猫", expected: "只有一隻貓"),
    ConversionCase(source: "制作制度", expected: "製作制度"),
]

for testCase in phraseCases {
    let converted = IosChineseTextConverter.convert(testCase.source, to: .traditional)
    expectEqual(converted, testCase.expected, source: testCase.source)
}

private let simplified = "里面头发发展干嘛面条"
expectEqual(
    IosChineseTextConverter.convert(simplified, to: .simplified),
    simplified,
    source: "simplified passthrough"
)

print("iOS Chinese text converter regression passed")
