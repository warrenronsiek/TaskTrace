//
//  Utils.swift
//  TaskTrace
//
//  Created by Warren Ronsiek on 3/14/26.
//

public func concurrentFlatMap<Input, Output: Sendable>(
    _ inputs: [Input],
    transform: @escaping @Sendable (Input) async -> [Output]
) async -> [Output] where Input: Sendable {
    await withTaskGroup(of: [Output].self, returning: [Output].self) { group in
        for input in inputs {
            group.addTask {
                await transform(input)
            }
        }

        var result: [Output] = []

        for await outputs in group {
            result.append(contentsOf: outputs)
        }

        return result
    }
}
