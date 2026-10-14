import SwiftUI

public struct VideoQualitySheet: View {
    public let metadata: VideoMetadata
    public let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormatId: String = "best"

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let thumbStr = metadata.thumbnail, let thumbUrl = URL(string: thumbStr) {
                    AsyncImage(url: thumbUrl) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                    .frame(width: 80, height: 50)
                    .cornerRadius(4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(metadata.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text("选择下载清晰度与格式:")
                .font(.subheadline.bold())

            List(selection: $selectedFormatId) {
                Text("🔥 最佳画质与音质自动混流 (推荐)")
                    .tag("bestvideo+bestaudio/best")

                Text("🎵 仅提取最高品质音频 (MP3/M4A)")
                    .tag("bestaudio/best")

                Section("可选清晰度列表") {
                    ForEach(metadata.formats) { f in
                        HStack {
                            Text(f.displayLabel)
                            Spacer()
                            if f.hasVideo && f.hasAudio {
                                Text("音视频整合")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(2)
                            } else if f.hasVideo {
                                Text("纯视频")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(2)
                            } else if f.hasAudio {
                                Text("纯音频")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(2)
                            }
                        }
                        .tag(f.formatId)
                    }
                }
            }
            .listStyle(.inset)
            .frame(height: 200)

            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("确定下载") {
                    onSelect(selectedFormatId)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520, height: 360)
    }
}
