//
//  PhotoGridView.swift
//  Photo2drive
//

import SwiftUI

/// Grid view displaying selected photos.
struct PhotoGridView: View {
    let photoItems: [PhotoItem]
    let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(photoItems) { item in
                    PhotoThumbnailView(photoItem: item)
                }
            }
            .padding()
        }
    }
}

/// Thumbnail view for a single photo.
struct PhotoThumbnailView: View {
    let photoItem: PhotoItem

    var body: some View {
        Group {
            if let thumbnail = photoItem.thumbnail {
                thumbnail
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.gray)
                    }
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    PhotoGridView(photoItems: [])
}
