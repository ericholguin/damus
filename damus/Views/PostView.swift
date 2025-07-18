//
//  Post.swift
//  damus
//
//  Created by William Casarin on 2022-04-03.
//

import SwiftUI
import AVKit
import Kingfisher

enum NostrPostResult {
    case post(NostrPost)
    case cancel
}

let POST_PLACEHOLDER = NSLocalizedString("Type your note here...", comment: "Text box prompt to ask user to type their note.")
let GHOST_CARET_VIEW_ID = "GhostCaret"
let DEBUG_SHOW_GHOST_CARET_VIEW: Bool = false

class TagModel: ObservableObject {
    var diff = 0
}

enum PostTarget {
    case none
    case user(Pubkey)
}

enum PostAction {
    case replying_to(NostrEvent)
    case quoting(NostrEvent)
    case posting(PostTarget)
    case highlighting(HighlightContentDraft)
    case sharing(ShareContent)
    
    var ev: NostrEvent? {
        switch self {
            case .replying_to(let ev):
                return ev
            case .quoting(let ev):
                return ev
            case .posting:
                return nil
            case .highlighting:
                return nil
            case .sharing(_):
                return nil
        }
    }
}

struct PostView: View {
    
    @State var post: NSMutableAttributedString = NSMutableAttributedString()
    @State var uploadedMedias: [UploadedMedia] = []
    @State var references: [RefId] = []
    /// Pubkeys that should be filtered out from the references
    ///
    /// For example, when replying to an event, the user can select which pubkey mentions they want to keep, and which ones to remove.
    @State var filtered_pubkeys: Set<Pubkey> = []
    
    @FocusState var focus: Bool
    @State var attach_media: Bool = false
    @State var attach_camera: Bool = false
    @State var error: String? = nil
    @State var image_upload_confirm: Bool = false
    @State var imagePastedFromPasteboard: PreUploadedMedia? = nil
    @State var imageUploadConfirmPasteboard: Bool = false
    @State var imageUploadConfirmDamusShare: Bool = false
    @State var focusWordAttributes: (String?, NSRange?) = (nil, nil)
    @State var newCursorIndex: Int?
    @State var textHeight: CGFloat? = nil
    /// Manages the auto-save logic for drafts.
    ///
    /// ## Implementation notes
    ///
    /// - This intentionally does _not_ use `@ObservedObject` or `@StateObject` because observing changes causes unwanted automatic scrolling to the text cursor on each save state update.
    var autoSaveModel: AutoSaveIndicatorView.AutoSaveViewModel

    @State var preUploadedMedia: [PreUploadedMedia] = []
    @State var mediaUploadUnderProgress: MediaUpload? = nil
    
    @StateObject var image_upload: ImageUploadModel = ImageUploadModel()
    @StateObject var tagModel: TagModel = TagModel()
    
    @State private var current_placeholder_index = 0
    @State private var uploadTasks: [Task<Void, Never>] = []

    let action: PostAction
    let damus_state: DamusState
    let prompt_view: (() -> AnyView)?
    let placeholder_messages: [String]
    let initial_text_suffix: String?
    
    init(
        action: PostAction,
        damus_state: DamusState,
        prompt_view: (() -> AnyView)? = nil,
        placeholder_messages: [String]? = nil,
        initial_text_suffix: String? = nil
    ) {
        self.action = action
        self.damus_state = damus_state
        self.prompt_view = prompt_view
        self.placeholder_messages = placeholder_messages ?? [POST_PLACEHOLDER]
        self.initial_text_suffix = initial_text_suffix
        self.autoSaveModel = AutoSaveIndicatorView.AutoSaveViewModel(save: { damus_state.drafts.save(damus_state: damus_state) })
    }

    @Environment(\.dismiss) var dismiss

    func cancel() {
        notify(.post(.cancel))
        cancelUploadTasks()
        dismiss()
    }
    
    func cancelUploadTasks() {
        uploadTasks.forEach { $0.cancel() }
        uploadTasks.removeAll()
    }
    
    func send_post() {
        let new_post = build_post(state: self.damus_state, post: self.post, action: action, uploadedMedias: uploadedMedias, references: self.references, filtered_pubkeys: filtered_pubkeys)

        notify(.post(.post(new_post)))

        clear_draft()

        dismiss()

    }

    var is_post_empty: Bool {
        return post.string.allSatisfy { $0.isWhitespace } && uploadedMedias.isEmpty
    }

    var uploading_disabled: Bool {
        return image_upload.progress != nil
    }

    var posting_disabled: Bool {
        switch action {
            case .highlighting(_):
                return false
            default:
                return is_post_empty || uploading_disabled
        }
    }
    
    // Returns a valid height for the text box, even when textHeight is not a number
    func get_valid_text_height() -> CGFloat {
        if let textHeight, textHeight.isFinite, textHeight > 0 {
            return textHeight
        }
        else {
            return 10
        }
    }
    
    var ImageButton: some View {
        Button(action: {
            preUploadedMedia.removeAll()
            attach_media = true
        }, label: {
            Image("images")
                .padding(6)
        })
    }
    
    var CameraButton: some View {
        Button(action: {
            attach_camera = true
        }, label: {
            Image("camera")
                .padding(6)
        })
    }
    
    var AttachmentBar: some View {
        HStack(alignment: .center, spacing: 15) {
            ImageButton
            CameraButton
            Spacer()
            AutoSaveIndicatorView(saveViewModel: self.autoSaveModel)
        }
        .disabled(uploading_disabled)
    }
    
    var PostButton: some View {
        Button(NSLocalizedString("Post", comment: "Button to post a note.")) {
            self.send_post()
        }
        .disabled(posting_disabled)
        .opacity(posting_disabled ? 0.5 : 1.0)
        .bold()
        .buttonStyle(GradientButtonStyle(padding: 10))
        
    }
    
    func isEmpty() -> Bool {
        return self.uploadedMedias.count == 0 &&
            self.post.mutableString.trimmingCharacters(in: .whitespacesAndNewlines) ==
                initialString().mutableString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func initialString() -> NSMutableAttributedString {
        guard case .posting(let target) = action,
              case .user(let pubkey) = target,
              damus_state.pubkey != pubkey else {
            return .init(string: "")
        }
        
        let profile_txn = damus_state.profiles.lookup(id: pubkey)
        let profile = profile_txn?.unsafeUnownedValue
        return user_tag_attr_string(profile: profile, pubkey: pubkey)
    }
    
    func clear_draft() {
        switch action {
            case .replying_to(let replying_to):
                damus_state.drafts.replies.removeValue(forKey: replying_to.id)
            case .quoting(let quoting):
                damus_state.drafts.quotes.removeValue(forKey: quoting.id)
            case .posting:
                damus_state.drafts.post = nil
            case .highlighting(let draft):
                damus_state.drafts.highlights.removeValue(forKey: draft)
            case .sharing(_):
                damus_state.drafts.post = nil
        }

        damus_state.drafts.save(damus_state: damus_state)
    }
    
    func load_draft() -> Bool {
        guard let draft = load_draft_for_post(drafts: self.damus_state.drafts, action: self.action) else {
            self.post = NSMutableAttributedString("")
            self.uploadedMedias = []
            self.autoSaveModel.markNothingToSave()   // We should not save empty drafts.
            return false
        }
        
        self.uploadedMedias = draft.media
        self.post = draft.content
        self.autoSaveModel.markSaved()  // The draft we just loaded is saved to memory. Mark it as such.
        return true
    }
    
    /// Use this to signal that the post contents have changed. This will do two things:
    /// 
    /// 1. Save the new contents into our in-memory drafts
    /// 2. Signal that we need to save drafts persistently, which will happen after a certain wait period
    func post_changed(post: NSMutableAttributedString, media: [UploadedMedia]) {
        if let draft = load_draft_for_post(drafts: damus_state.drafts, action: action) {
            draft.content = post
            draft.media = uploadedMedias
            draft.references = references
            draft.filtered_pubkeys = filtered_pubkeys
        } else {
            let artifacts = DraftArtifacts(content: post, media: uploadedMedias, references: references, id: UUID().uuidString)
            set_draft_for_post(drafts: damus_state.drafts, action: action, artifacts: artifacts)
        }
        self.autoSaveModel.needsSaving()
    }
    
    var TextEntry: some View {
        ZStack(alignment: .topLeading) {
            TextViewWrapper(
                attributedText: $post,
                textHeight: $textHeight,
                initialTextSuffix: initial_text_suffix,
                imagePastedFromPasteboard: $imagePastedFromPasteboard,
                imageUploadConfirmPasteboard: $imageUploadConfirmPasteboard,
                cursorIndex: newCursorIndex,
                getFocusWordForMention: { word, range in
                    focusWordAttributes = (word, range)
                    self.newCursorIndex = nil
                }, 
                updateCursorPosition: { newCursorIndex in
                    self.newCursorIndex = newCursorIndex
                }
            )
                .environmentObject(tagModel)
                .focused($focus)
                .textInputAutocapitalization(.sentences)
                .onChange(of: post) { p in
                    post_changed(post: p, media: uploadedMedias)
                }
                // Set a height based on the text content height, if it is available and valid
                .frame(height: get_valid_text_height())
            
            if post.string.isEmpty {
                Text(self.placeholder_messages[self.current_placeholder_index])
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .foregroundColor(Color(uiColor: .placeholderText))
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            // Schedule a timer to switch messages every 3 seconds
            Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { timer in
                withAnimation {
                    self.current_placeholder_index = (self.current_placeholder_index + 1) % self.placeholder_messages.count
                }
            }
        }
    }
    
    var TopBar: some View {
        VStack {
            HStack(spacing: 5.0) {
                Button(action: {
                    self.cancel()
                }, label: {
                    Text("Cancel", comment: "Button to cancel out of posting a note.")
                        .padding(10)
                })
                .buttonStyle(NeutralButtonStyle())
                .accessibilityIdentifier(AppAccessibilityIdentifiers.post_composer_cancel_button.rawValue)
                
                if let error {
                    Text(error)
                        .foregroundColor(.red)
                }

                Spacer()

                PostButton
            }
            
            Divider()
                .foregroundColor(DamusColors.neutral3)
                .padding(.top, 5)
        }
        .frame(height: 30)
        .padding()
        .padding(.top, 15)
    }

    @discardableResult
    func handle_upload(media: MediaUpload) async -> Bool {
        mediaUploadUnderProgress = media
        let uploader = damus_state.settings.default_media_uploader
        
        let img = getImage(media: media)
        print("img size w:\(img.size.width) h:\(img.size.height)")
        
        async let blurhash = calculate_blurhash(img: img)
        let res = await image_upload.start(media: media, uploader: uploader, mediaType: .normal, keypair: damus_state.keypair)
        
        mediaUploadUnderProgress = nil
        switch res {
        case .success(let url):
            guard let url = URL(string: url) else {
                self.error = "Error uploading image :("
                return false
            }
            let blurhash = await blurhash
            let meta = blurhash.map { bh in calculate_image_metadata(url: url, img: img, blurhash: bh) }
            let uploadedMedia = UploadedMedia(localURL: media.localURL, uploadedURL: url, metadata: meta)
            uploadedMedias.append(uploadedMedia)
            return true
            
        case .failed(let error):
            if let error {
                self.error = error.localizedDescription
            } else {
                self.error = "Error uploading image :("
            }
            return false
        }
    }
    
    var multiply_factor: CGFloat {
        if case .quoting = action {
            return 0.4
        } else if !uploadedMedias.isEmpty {
            return 0.2
        } else {
            return 1.0
        }
    }
    
    func Editor(deviceSize: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ProfilePicView(pubkey: damus_state.pubkey, size: PFP_SIZE, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)
                    
                    VStack(alignment: .leading) {
                        if let prompt_view {
                            prompt_view()
                        }
                        TextEntry
                    }
                }
                .id("post")
                
                PVImageCarouselView(media: $uploadedMedias,
                                    mediaUnderProgress: $mediaUploadUnderProgress,
                                    imageUploadModel: image_upload,
                                    deviceWidth: deviceSize.size.width)
                        .onChange(of: uploadedMedias) { media in
                            post_changed(post: post, media: media)
                }
                
                if case .quoting(let ev) = action {
                    BuilderEventView(damus: damus_state, event: ev)
                }
                else if case .highlighting(let draft) = action {
                    HighlightDraftContentView(draft: draft)
                }
                else if case .sharing(let draft) = action,
                        let url = draft.getLinkURL() {
                    LinkViewRepresentable(meta: .url(url))
                        .frame(height: 50)
                }
            }
            .padding(.horizontal)
        }
    }
    
    func fill_target_content(target: PostTarget) {
        self.post = initialString()
        self.tagModel.diff = post.string.count
    }

    var pubkeys: [Pubkey] {
        self.references.reduce(into: [Pubkey]()) { pks, ref in
            guard case .pubkey(let pk) = ref else {
                return
            }

            pks.append(pk)
        }
    }

    var body: some View {
        GeometryReader { (deviceSize: GeometryProxy) in
            VStack(alignment: .leading, spacing: 0) {
                let searching = get_searching_string(focusWordAttributes.0)
                let searchingHashTag = get_searching_hashTag(focusWordAttributes.0)
                TopBar
                
                ScrollViewReader { scroller in
                    ScrollView {
                        VStack(alignment: .leading) {
                            if case .replying_to(let replying_to) = self.action {
                                ReplyView(replying_to: replying_to, damus: damus_state, original_pubkeys: pubkeys, filtered_pubkeys: $filtered_pubkeys)
                            }
                            
                            Editor(deviceSize: deviceSize)
                                .padding(.top, 5)
                        }
                    }
                    .frame(maxHeight: searching == nil && searchingHashTag == nil ? deviceSize.size.height : 70)
                    .onAppear {
                        scroll_to_event(scroller: scroller, id: "post", delay: 1.0, animate: true, anchor: .top)
                    }
                }
                
                // This if-block observes @ for tagging
                if let searching {
                    UserSearch(damus_state: damus_state, search: searching, focusWordAttributes: $focusWordAttributes, newCursorIndex: $newCursorIndex, post: $post)
                        .frame(maxHeight: .infinity)
                        .environmentObject(tagModel)
                // This else observes '#' for hash-tag suggestions and creates SuggestedHashtagsView
                } else if let searchingHashTag {
                        SuggestedHashtagsView(damus_state: damus_state,
                                              events: SearchHomeModel(damus_state: damus_state).events,
                                              isFromPostView: true,
                                              queryHashTag: searchingHashTag,
                                              focusWordAttributes: $focusWordAttributes,
                                              newCursorIndex: $newCursorIndex,
                                              post: $post)
                        .environmentObject(tagModel)
               } else {
                    Divider()
                    VStack(alignment: .leading) {
                        AttachmentBar
                            .padding(.vertical, 5)
                            .padding(.horizontal)
                    }
                }
            }
            .background(DamusColors.adaptableWhite.edgesIgnoringSafeArea(.all))
            .sheet(isPresented: $attach_media) {
                MediaPicker(mediaPickerEntry: .postView, onMediaSelected: { image_upload_confirm = true }) { media in
                    self.preUploadedMedia.append(media)
                }
                .alert(NSLocalizedString("Are you sure you want to upload the selected media?", comment: "Alert message asking if the user wants to upload media."), isPresented: $image_upload_confirm) {
                    Button(NSLocalizedString("Upload", comment: "Button to proceed with uploading."), role: .none) {
                        // initiate asynchronous uploading Task for multiple-images
                        let task = Task {
                            for media in preUploadedMedia {
                                if let mediaToUpload = generateMediaUpload(media) {
                                    await self.handle_upload(media: mediaToUpload)
                                }
                            }
                        }
                        uploadTasks.append(task)
                        self.attach_media = false
                    }
                    Button(NSLocalizedString("Cancel", comment: "Button to cancel the upload."), role: .cancel) {
                        preUploadedMedia.removeAll()
                    }
                }
            }
            .sheet(isPresented: $attach_camera) {
                CameraController(uploader: damus_state.settings.default_media_uploader, mode: .save_to_library(when_done: {
                    self.attach_camera = false
                    self.attach_media = true
                }))
            }
            // This alert seeks confirmation about Image-upload when user taps Paste option
            .alert(NSLocalizedString("Are you sure you want to upload this media?", comment: "Alert message asking if the user wants to upload media."), isPresented: $imageUploadConfirmPasteboard) {
                Button(NSLocalizedString("Upload", comment: "Button to proceed with uploading."), role: .none) {
                    if let image = imagePastedFromPasteboard,
                       let mediaToUpload = generateMediaUpload(image) {
                        let task = Task {
                            _ = await self.handle_upload(media: mediaToUpload)
                        }
                        uploadTasks.append(task)
                    }
                }
                Button(NSLocalizedString("Cancel", comment: "Button to cancel the upload."), role: .cancel) {}
            }
            // This alert seeks confirmation about media-upload from Damus Share Extension
            .alert(NSLocalizedString("Are you sure you want to upload the selected media?", comment: "Alert message asking if the user wants to upload media."), isPresented: $imageUploadConfirmDamusShare) {
                Button(NSLocalizedString("Upload", comment: "Button to proceed with uploading."), role: .none) {
                    let task = Task {
                        for media in preUploadedMedia {
                            if let mediaToUpload = generateMediaUpload(media) {
                                await self.handle_upload(media: mediaToUpload)
                            }
                        }
                    }
                    uploadTasks.append(task)
                }
                Button(NSLocalizedString("Cancel", comment: "Button to cancel the upload."), role: .cancel) {}
            }
            .onAppear() {
                let loaded_draft = load_draft()
                
                switch action {
                    case .replying_to(let replying_to):
                        references = gather_reply_ids(our_pubkey: damus_state.pubkey, from: replying_to)
                    case .quoting(let quoting):
                        references = gather_quote_ids(our_pubkey: damus_state.pubkey, from: quoting)
                    case .posting(let target):
                        guard !loaded_draft else { break }
                        fill_target_content(target: target)
                    case .highlighting(let draft):
                        references = [draft.source.ref()]
                    case .sharing(let content):
                        if let url = content.getLinkURL() {
                            self.post = NSMutableAttributedString(string: "\(content.title)\n\(String(url.absoluteString))")
                        } else {
                            self.preUploadedMedia = content.getMediaArray()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self.imageUploadConfirmDamusShare = true // display Confirm Sheet after 1 sec
                            }
                        }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.focus = true
                }
            }
            .onDisappear {
                if isEmpty() {
                    clear_draft()
                }
                preUploadedMedia.removeAll()
            }
        }
    }
}

func get_searching_string(_ word: String?) -> String? {
    guard let word = word else {
        return nil
    }

    guard word.count >= 2 else {
        return nil
    }
    
    guard let firstCharacter = word.first,
          firstCharacter == "@" else {
        return nil
    }
    
    // don't include @npub... strings
    guard word.count != 64 else {
        return nil
    }
    
    return String(word.dropFirst())
}

fileprivate func get_searching_hashTag(_ word: String?) -> String? {
    guard let word,
          word.count >= 2,
          let first_char = word.first,
          first_char == "#" else {
        return nil
    }
    
    return String(word.dropFirst())
}

struct PostView_Previews: PreviewProvider {
    static var previews: some View {
        PostView(action: .posting(.none), damus_state: test_damus_state)
    }
}

struct PVImageCarouselView: View {
    @Binding var media: [UploadedMedia]
    @Binding var mediaUnderProgress: MediaUpload?
    @ObservedObject var imageUploadModel: ImageUploadModel

    let deviceWidth: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(media.indices, id: \.self) { index in
                    ZStack(alignment: .topLeading) {
                        if isSupportedVideo(url: media[index].uploadedURL) {
                            VideoPlayer(player: configurePlayer(with: media[index].localURL))
                                .frame(width: media.count == 1 ? deviceWidth * 0.8 : 250, height: media.count == 1 ? 400 : 250)
                                .cornerRadius(10)
                                .padding()
                                .contextMenu { contextMenuContent(for: media[index]) }
                        } else {
                            KFAnimatedImage(media[index].uploadedURL)
                                .imageContext(.note, disable_animation: false)
                                .configure { view in
                                    view.framePreloadCount = 3
                                }
                                .frame(width: media.count == 1 ? deviceWidth * 0.8 : 250, height: media.count == 1 ? 400 : 250)
                                .cornerRadius(10)
                                .padding()
                                .contextMenu { contextMenuContent(for: media[index]) }
                        }
                        
                        VStack {  // Set spacing to 0 to remove the gap between items
                            Image("close-circle")
                                .foregroundColor(.white)
                                .padding(20)
                                .shadow(radius: 5)
                                .onTapGesture {
                                    media.remove(at: index) // Direct removal using index
                                }
                            
                            if isSupportedVideo(url: media[index].uploadedURL) {
                                Spacer()
                                    Image(systemName: "video")
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .shadow(radius: 5)
                                        .opacity(0.6)
                                }
                        }
                        .padding(.bottom, 35)
                    }
                }
                if let mediaUP = mediaUnderProgress, let progress = imageUploadModel.progress {
                    ZStack {
                        // Media under upload-progress
                        Image(uiImage: getImage(media: mediaUP))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: media.count == 0 ? deviceWidth * 0.8 : 250, height: media.count == 0 ? 400 : 250)
                            .cornerRadius(10)
                            .opacity(0.3)
                            .padding()
                        // Circle showing progress on top of media
                        Circle()
                            .trim(from: 0, to: CGFloat(progress))
                            .stroke(Color.damusPurple, lineWidth: 5.0)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 30, height: 30)
                            .padding()
                    }
                }
            }
            .padding()
        }
    }
    
    // Helper Function for Context Menu
    @ViewBuilder
    private func contextMenuContent(for mediaItem: UploadedMedia) -> some View {
        Button(action: {
            UIPasteboard.general.string = mediaItem.uploadedURL.absoluteString
        }) {
            Label(
                NSLocalizedString("Copy URL", comment: "Copy URL of the selected uploaded media asset."),
                systemImage: "doc.on.doc"
            )
        }
    }
    
    private func configurePlayer(with url: URL) -> AVPlayer {
        let player = AVPlayer(url: url)
        player.allowsExternalPlayback = false
        player.usesExternalPlaybackWhileExternalScreenIsActive = false
        return player
    }
}

fileprivate func getImage(media: MediaUpload) -> UIImage {
    var uiimage: UIImage = UIImage()
    if media.is_image {
        // fetch the image data
        if let data = try? Data(contentsOf: media.localURL) {
            uiimage = UIImage(data: data) ?? UIImage()
        }
    } else {
        let asset = AVURLAsset(url: media.localURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTimeMake(value: 1, timescale: 60) // get the thumbnail image at the 1st second
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            uiimage = UIImage(cgImage: cgImage)
        } catch {
            print("No thumbnail: \(error)")
        }
        // create a play icon on the top to differentiate if media upload is image or a video, gif is an image
        let playIcon = UIImage(systemName: "play.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
        let size = uiimage.size
        let scale = UIScreen.main.scale
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        uiimage.draw(at: .zero)
        let playIconSize = CGSize(width: 60, height: 60)
        let playIconOrigin = CGPoint(x: (size.width - playIconSize.width) / 2, y: (size.height - playIconSize.height) / 2)
        playIcon?.draw(in: CGRect(origin: playIconOrigin, size: playIconSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        uiimage = newImage ?? UIImage()
    }
    return uiimage
}

struct UploadedMedia: Equatable {
    let localURL: URL
    let uploadedURL: URL
    let metadata: ImageMetadata?
}


func set_draft_for_post(drafts: Drafts, action: PostAction, artifacts: DraftArtifacts) {
    switch action {
    case .replying_to(let ev):
        drafts.replies[ev.id] = artifacts
    case .quoting(let ev):
        drafts.quotes[ev.id] = artifacts
    case .posting:
        drafts.post = artifacts
    case .highlighting(let draft):
        drafts.highlights[draft] = artifacts
    case .sharing(_):
        drafts.post = artifacts
    }
}

func load_draft_for_post(drafts: Drafts, action: PostAction) -> DraftArtifacts? {
    switch action {
    case .replying_to(let ev):
        return drafts.replies[ev.id]
    case .quoting(let ev):
        return drafts.quotes[ev.id]
    case .posting:
        return drafts.post
    case .highlighting(let highlight):
        if let exact_match = drafts.highlights[highlight] {
            return exact_match  // Always prefer to return the draft for that exact same highlight
        }
        // If there are no exact matches to the highlight, try to load a draft for the same highlight source
        // We do this to improve UX, because we don't want to leave the post view blank if they only selected a slightly different piece of text from before.
        let other_matches = drafts.highlights
            .filter { $0.key.source == highlight.source }
        // It's not an exact match, so there is no way of telling which one is the preferred draft. So just load the first one we found.
        return other_matches.first?.value
    case .sharing(_):
        return drafts.post
    }
}

private func isAlphanumeric(_ char: Character) -> Bool {
    return char.isLetter || char.isNumber
}

func nip10_reply_tags(replying_to: NostrEvent, keypair: Keypair) -> [[String]] {
    guard let nip10 = replying_to.thread_reply() else {
        // we're replying to a post that isn't in a thread,
        // just add a single reply-to-root tag
        return [["e", replying_to.id.hex(), "", "root"]]
    }

    // otherwise use the root tag from the parent's nip10 reply and include the note
    // that we are replying to's note id.
    let tags = [
        ["e", nip10.root.note_id.hex(), nip10.root.relay ?? "", "root"],
        ["e", replying_to.id.hex(), "", "reply"]
    ]

    return tags
}

func build_post(state: DamusState, action: PostAction, draft: DraftArtifacts) -> NostrPost {
    return build_post(
        state: state,
        post: draft.content,
        action: action,
        uploadedMedias: draft.media,
        references: draft.references,
        filtered_pubkeys: draft.filtered_pubkeys
    )
}

func build_post(state: DamusState, post: NSAttributedString, action: PostAction, uploadedMedias: [UploadedMedia], references: [RefId], filtered_pubkeys: Set<Pubkey>) -> NostrPost {
    // don't add duplicate pubkeys but retain order
    var pkset = Set<Pubkey>()

    // we only want pubkeys really
    let pks = references.reduce(into: Array<Pubkey>()) { acc, ref in
        guard case .pubkey(let pk) = ref else {
            return
        }
        
        if pkset.contains(pk) || filtered_pubkeys.contains(pk) {
            return
        }

        pkset.insert(pk)
        acc.append(pk)
    }
    
    return build_post(state: state, post: post, action: action, uploadedMedias: uploadedMedias, pubkeys: pks)
}

/// This builds a Nostr post from draft data from `PostView` or other draft-related classes
///
/// ## Implementation notes
///
/// - This function _likely_ causes no side-effects, and _should not_ cause side-effects to any of the inputs.
///
/// - Parameters:
///   - state: The damus state, needed to fetch more Nostr data to form this event
///   - post: The text content from `PostView`.
///   - action: The intended action of the post (highlighting? replying?)
///   - uploadedMedias: The medias attached to this post
///   - pubkeys: The referenced pubkeys
/// - Returns: A NostrPost, which can then be signed into an event.
func build_post(state: DamusState, post: NSAttributedString, action: PostAction, uploadedMedias: [UploadedMedia], pubkeys: [Pubkey]) -> NostrPost {
    let post = NSMutableAttributedString(attributedString: post)
    post.enumerateAttributes(in: NSRange(location: 0, length: post.length), options: []) { attributes, range, stop in
        let linkValue = attributes[.link]
        let link = (linkValue as? String) ?? (linkValue as? URL)?.absoluteString
        if let link {
            let nextCharIndex = range.upperBound
            if nextCharIndex < post.length,
               let nextChar = post.attributedSubstring(from: NSRange(location: nextCharIndex, length: 1)).string.first,
               isAlphanumeric(nextChar) {
                post.insert(NSAttributedString(string: " "), at: nextCharIndex)
            }

            let normalized_link: String
            if link.hasPrefix("damus:nostr:") {
                // Replace damus:nostr: URI prefix with nostr: since the former is for internal navigation and not meant to be posted.
                normalized_link = String(link.dropFirst(6))
            } else {
                normalized_link = link
            }

            // Add zero-width space in case text preceding the mention is not a whitespace.
            // In the case where the character preceding the mention is a whitespace, the added zero-width space will be stripped out.
            post.replaceCharacters(in: range, with: "\(normalized_link)")
        }
    }


    var content = post.string
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let imagesString = uploadedMedias.map { $0.uploadedURL.absoluteString }.joined(separator: "\n")

    if !imagesString.isEmpty {
        content.append("\n\n" + imagesString)
    }

    var tags: [[String]] = []

    switch action {
    case .replying_to(let replying_to):
        // start off with the reply tags
        tags = nip10_reply_tags(replying_to: replying_to, keypair: state.keypair)

    case .quoting(let ev):
        content.append("\n\nnostr:" + bech32_note_id(ev.id))

        tags.append(["q", ev.id.hex()]);

        if let quoted_ev = state.events.lookup(ev.id) {
            tags.append(["p", quoted_ev.pubkey.hex()])
        }
    case .posting, .highlighting, .sharing:
        break
    }

    // append additional tags
    tags += uploadedMedias.compactMap { $0.metadata?.to_tag() }
    
    switch action {
        case .highlighting(let draft):
            tags.append(contentsOf: draft.source.tags())
            if !(content.isEmpty || content.allSatisfy { $0.isWhitespace })  {
                tags.append(["comment", content])
            }
            tags += pubkeys.map { pk in
                ["p", pk.hex(), "mention"]
            }
            return NostrPost(content: draft.selected_text, kind: .highlight, tags: tags)
        default:
            tags += pubkeys.map { pk in
                ["p", pk.hex()]
            }
    }

    return NostrPost(content: content.trimmingCharacters(in: .whitespacesAndNewlines), kind: .text, tags: tags)
}

func isSupportedVideo(url: URL?) -> Bool {
    guard let url = url else { return false }
    let fileExtension = url.pathExtension.lowercased()
    let supportedUTIs = AVURLAsset.audiovisualTypes().map { $0.rawValue }
    return supportedUTIs.contains { utiString in
        if let utType = UTType(utiString), let fileUTType = UTType(filenameExtension: fileExtension) {
            return fileUTType.conforms(to: utType)
        }
        return false
    }
}

func isSupportedImage(url: URL) -> Bool {
    let fileExtension = url.pathExtension.lowercased()
    // It would be better to pull this programmatically from Apple's APIs, but there seems to be no such call
    let supportedTypes = ["jpg", "png", "gif"]
    return supportedTypes.contains(fileExtension)
}

