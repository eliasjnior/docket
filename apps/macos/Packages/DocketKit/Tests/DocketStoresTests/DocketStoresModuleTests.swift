import DocketStores
import DocketTestSupport
import Testing

@Test func moduleIsLinked() {
    #expect(DocketStoresModule.name == "DocketStores")
    #expect(Fixtures.you == "you")
}
