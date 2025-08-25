/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
An observable state object that contains profile details.
*/

import SwiftUI
import PhotosUI
// 외부 데이터(ex.사진)을 나의 타입으로 변환함을 명확히 선언
import CoreTransferable

// 해당 객체의 모든 프로퍼티의 get/set은 메인 액터(메인 스레드)에서 일어나도록 보장 - UI 상태를 다루기 때문

@MainActor
class ProfileModel: ObservableObject {
    
	// MARK: - Profile Details
    
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var aboutMe: String = ""
    
    // MARK: - Profile Image
    
    // 명시적인 이미지 상태 머신
    enum ImageState {
        case empty
		case loading(Progress)
		case success(Image)
		case failure(Error)
    }
    
    enum TransferError: Error {
        case importFailed
    }
    
    // Treansferable : 전송/가져오기 규약
    struct ProfileImage: Transferable {
        let image: Image
        
        static var transferRepresentation: some TransferRepresentation {
            // DataRepresentation(importedContentType: .image) : UTType.image 계열(PNG, JPEF, HEIF 등)을 받았을때만 이 변환 로직을 사용함을 명시
            DataRepresentation(importedContentType: .image) { data in
            #if canImport(AppKit)
                guard let nsImage = NSImage(data: data) else {
                    throw TransferError.importFailed
                }
                let image = Image(nsImage: nsImage)
                return ProfileImage(image: image)
            #elseif canImport(UIKit)
                guard let uiImage = UIImage(data: data) else {
                    throw TransferError.importFailed
                }
                let image = Image(uiImage: uiImage)
                return ProfileImage(image: image)
            #else
                throw TransferError.importFailed
            #endif
            }
        }
    }
    
    // get은 공개, set은 내부만 허용 -> View는 imageState를 구독해 UI 랜더링하지만, 상태 변경은 오직 모델 내부 로직만 수행할 수 있도록 제어
    @Published private(set) var imageState: ImageState = .empty
    
    @Published var imageSelection: PhotosPickerItem? = nil {
        // 사용자가 사진을 고르는 즉시 didset 호출
        didSet {
            // 사진이 선택됐으면 loadTransferable로 비동기 로딩 시작과 동시에 imageState가 .loading(progress)로 전환
            if let imageSelection {
                let progress = loadTransferable(from: imageSelection)
                imageState = .loading(progress)
            // 사진 선택이 해제되면(if imageSelection == nil)
            } else {
                imageState = .empty
            }
        }
    }
    
	// MARK: - Private Methods
	
    // 실제 로딩(비동기 작업) : 선택한 사진을 실제 이미지 데이터로 변환하는데는 시간이 걸리고, 그 결과는 나중에 클로저로 돌아옴
    // PhotosPickerItem.loadTransferable(클로저)는 즉시 Progress를 반환하고, 변환이 끝나면 결과를 클로저로 전달 -> UI는 바로 ProgressView를 띄운 후, 작업이 완료되면 이미지를 보여줌
    private func loadTransferable(from selectedItem: PhotosPickerItem) -> Progress {
        return selectedItem.loadTransferable(type: ProfileImage.self) { result in
            // 클래스가 @MainActor이지만 loadTransferable의 완료 클로저는 비메인 context에서 호출될 수 있음
            // DispatchQueue.main.async로 명시적으로 메인으로 복귀한 뒤 imageState를 변경
            DispatchQueue.main.async {
                // guard : 비동기 결과가 뒤늦게 와도, 사용자가 지금 실제로 고른 최신 항목인지 확인 후 반영하는 필터 역할
                /*
                    사용자가 사진 A를 고른다.
                    → loadTransferable(from: A) 실행 → 백그라운드에서 이미지 A를 읽고 변환 중.
                    
                    변환이 아직 끝나기 전에 사용자가 사진 B를 고른다.
                    → imageSelection이 B로 바뀌면서 loadTransferable(from: B) 실행 → 백그라운드에서 이미지 B 읽기 시작.
                    
                    그런데 사진 A의 변환이 먼저 끝나버림.
                    → A의 결과가 클로저로 전달됨
               */
                // imageSelection(앞) : 클로저 실행 시점에 캡처된 항목 A
                // imageSelection(뒤) : viewModel이 현재 들고 있는 항목 B
                guard selectedItem == self.imageSelection else {
                    print("Failed to get the selected item.")
                    return
                }
                switch result {
                case .success(let profileImage?):
                    self.imageState = .success(profileImage.image)
                case .success(nil):
                    self.imageState = .empty
                case .failure(let error):
                    self.imageState = .failure(error)
                }
            }
        }
    }
}
