import Foundation

public protocol GraphExecutableDefinitionLoading: Sendable {
    func load(path: String) throws -> GraphExecutableDefinition
}

public struct FileGraphExecutableDefinitionLoader:
    GraphExecutableDefinitionLoading,
    Sendable
{
    public init() {}

    public func load(path: String) throws -> GraphExecutableDefinition {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let definition = try JSONDecoder().decode(
            GraphExecutableDefinition.self,
            from: data
        )
        try definition.validate()
        return definition
    }
}
