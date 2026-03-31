#if canImport(WidgetKit)
import SwiftUI
import WidgetKit

@main
struct FuyaoWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            FuyaoLiveActivityWidget()
        }
    }
}
#endif
