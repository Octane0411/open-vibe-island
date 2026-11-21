import Testing
@testable import OpenIslandCore

struct StructuredReplyFormatterTests {
    @Test func formatsObjectAsKeyLinesInSourceOrder() {
        let reply = #"{"name":"卵石 Pebble","form":"掌心大小","material_color":"雾灰色","weight":42,"ok":true}"#
        #expect(StructuredReplyFormatter.readable(reply) == """
        - **name**: 卵石 Pebble
        - **form**: 掌心大小
        - **material color**: 雾灰色
        - **weight**: 42
        - **ok**: true
        """)
    }

    @Test func stripsCodeFenceAndJoinsArrays() {
        let reply = "```json\n{\"tags\":[\"a\",\"b\"],\"meta\":{\"x\":1}}\n```"
        #expect(StructuredReplyFormatter.readable(reply) == "- **tags**: a, b\n- **meta**: x 1")
    }

    @Test func formatsArrayOfObjectsAsBlocks() {
        #expect(StructuredReplyFormatter.readable(#"[{"a":"1"},{"a":"2"}]"#) == "- **a**: 1\n\n- **a**: 2")
    }

    @Test func leavesProseAndBrokenJSONUntouched() {
        #expect(StructuredReplyFormatter.readable("已完成测试任务。") == "已完成测试任务。")
        #expect(StructuredReplyFormatter.readable("{not json") == "{not json")
    }
}
