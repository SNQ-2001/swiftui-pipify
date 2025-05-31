//
//  Copyright 2022 • Sidetrack Tech Limited
//

import Pipify
import SwiftUI

struct BasicExample: View {
    @State var mode: Int = 0
    @State var counter: Int = 0
    @State var renderSize: CGSize = .zero
    
    @EnvironmentObject var controller: PipifyController
    
    var body: some View {
        Group {
            switch mode {
            case 0:
                VStack {
                    Text("Width: \(Int(renderSize.width))")
                    Text("Height: \(Int(renderSize.height))")
                }
                .foregroundColor(.green)
                .onPipTransitionToRenderSize(
                    onDidTransitionToRenderSize: { renderSize in
                        self.renderSize = renderSize
                    }
                )
            case 1:
                Text("Counter: \(counter)")
                    .foregroundColor(.blue)
                    .frame(width: 300, height: 100)
            default:
                Color.red
                    .overlay { Text("Counter: \(counter)").foregroundColor(.white) }
                    .frame(width: 100, height: 300)
            }
        }
        .task {
            await updateMode()
        }
        .task {
            await updateCounter()
        }
        .pipControlsStyle(.hidden)
    }
    
    private func updateCounter() async {
        counter += 1
        try? await Task.sleep(nanoseconds: 10_000_000) // 10 milliseconds
        await updateCounter()
    }
    
    private func updateMode() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000 * 5) // 5 seconds
        mode += 1
        
        if mode == 3 {
            mode = 0
        }
        
        await updateMode()
    }
}
