import DocketStores
import DocketTestSupport
import Testing

@Test func moduleIsLinked() {
    #expect(DocketStoresModule.name == "DocketStores")
    #expect(DocketTestSupportModule.name == "DocketTestSupport")
}
