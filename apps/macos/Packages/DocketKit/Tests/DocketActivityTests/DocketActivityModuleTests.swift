import DocketActivity
import DocketTestSupport
import Testing

@Test func moduleIsLinked() {
    #expect(DocketActivityModule.name == "DocketActivity")
    #expect(DocketTestSupportModule.name == "DocketTestSupport")
}
