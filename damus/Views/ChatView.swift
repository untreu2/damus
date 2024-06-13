//
//  ChatView.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import SwiftUI
import MCEmojiPicker

fileprivate let CORNER_RADIUS: CGFloat = 10

struct ChatView: View {
    let event: NostrEvent
    let selected_event: NostrEvent
    let prev_ev: NostrEvent?
    let next_ev: NostrEvent?

    let damus_state: DamusState
    var thread: ThreadModel
    let scroll_to_event: ((_ id: NoteId) -> Void)?
    let focus_event: (() -> Void)?
    let highlight_bubble: Bool
    @State var press = false

    let generator = UIImpactFeedbackGenerator(style: .medium)
    
    @State var expand_reply: Bool = false
    @State var selected_emoji: String = ""
    @State var popover_state: PopoverState = .closed {
        didSet {
            print(popover_state)
        }
    }
    @State private var isOnTopHalfOfScreen: Bool = false
    
    enum PopoverState: String {
        case closed
        case open
        case open_emoji_selector
        
        func is_open() -> Bool {
            return self == .open
        }
        
        mutating func set_open(_ is_open: Bool) {
            self = is_open == true ? .open : .closed
        }
    }

    var just_started: Bool {
        return prev_ev == nil || prev_ev!.pubkey != event.pubkey
    }

    func next_replies_to_this() -> Bool {
        guard let next = next_ev else {
            return false
        }

        return damus_state.events.replies.lookup(next.id) != nil
    }

    func is_reply_to_prev(ref_id: NoteId) -> Bool {
        guard let prev = prev_ev else {
            return true
        }

        if let rep = damus_state.events.replies.lookup(event.id) {
            return rep.contains(prev.id)
        }

        return false
    }

    var is_active: Bool {
        return thread.event.id == event.id
    }

    func prev_reply_is_same() -> NoteId? {
        return damus.prev_reply_is_same(event: event, prev_ev: prev_ev, replies: damus_state.events.replies)
    }

    func reply_is_new() -> NoteId? {
        guard let prev = self.prev_ev else {
            // if they are both null they are the same?
            return nil
        }

        if damus_state.events.replies.lookup(prev.id) != damus_state.events.replies.lookup(event.id) {
            return prev.id
        }

        return nil
    }

    @Environment(\.colorScheme) var colorScheme

    var disable_animation: Bool {
        self.damus_state.settings.disable_animation
    }

    var options: EventViewOptions {
        return [.no_previews, .no_action_bar, .truncate_content_very_short, .no_show_more, .no_translate, .no_media]
    }
    
    var profile_picture_view: some View {
        VStack {
            if is_active || just_started {
                ProfilePicView(pubkey: event.pubkey, size: 32, highlight: .none, profiles: damus_state.profiles, disable_animation: disable_animation)
                    .onTapGesture {
                        show_profile_action_sheet_if_enabled(damus_state: damus_state, pubkey: event.pubkey)
                    }
            }
        }
        .frame(maxWidth: 32)
    }
    
    var by_other_user: Bool {
        return event.pubkey != damus_state.pubkey
    }
    
    var is_ours: Bool { return !by_other_user }
    
    var event_bubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if by_other_user {
                    HStack {
                        ProfileName(pubkey: event.pubkey, damus: damus_state)
                            .foregroundColor(id_to_color(event.pubkey))
                            .onTapGesture {
                                show_profile_action_sheet_if_enabled(damus_state: damus_state, pubkey: event.pubkey)
                            }
                        Text(verbatim: "\(format_relative_time(event.created_at))")
                            .foregroundColor(.gray)
                    }
                }

                if let replying_to = event.direct_replies(),
                   replying_to != selected_event.id {
                    ReplyQuoteView(keypair: damus_state.keypair, quoter: event, event_id: replying_to, state: damus_state, thread: thread, options: options)
                        .background(is_ours ? DamusColors.adaptablePurpleBackground2 : DamusColors.adaptableGrey2)
                        .foregroundColor(is_ours ? Color.damusAdaptablePurpleForeground : Color.damusAdaptableBlack)
                        .cornerRadius(5)
                        .onTapGesture {
                            self.scroll_to_event?(replying_to)
                        }
                }
                
                HStack {
                    let blur_images = should_blur_images(settings: damus_state.settings, contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey)
                    NoteContentView(damus_state: damus_state, event: event, blur_images: blur_images, size: .normal, options: [])
                        .padding(2)
                    Spacer()
                }
            }
        }
        .padding(10)
        .background(by_other_user ? DamusColors.adaptableGrey : DamusColors.adaptablePurpleBackground)
        .tint(is_ours ? Color.white : Color.accentColor)
        .cornerRadius(CORNER_RADIUS)
        .padding(4)
        .overlay(
            RoundedRectangle(cornerRadius: CORNER_RADIUS+2)
                .stroke(.accent, lineWidth: 4)
                .opacity(highlight_bubble ? 1 : 0)
        )
        .onTapGesture {
            focus_event?()
        }
    }
    
    var event_bubble_wrapper: some View {
        self.event_bubble
            .emojiPicker(
                isPresented: Binding(get: { popover_state == .open_emoji_selector }, set: {
                    print("emoji picker presentation update: \($0.description)")
                    popover_state = $0 == true ? .open_emoji_selector : .closed
                }),
                selectedEmoji: $selected_emoji,
                arrowDirection: isOnTopHalfOfScreen ? .down : .up,
                isDismissAfterChoosing: false
            )
            .onChange(of: selected_emoji) { newSelectedEmoji in
                if newSelectedEmoji != "" {
                    send_like(emoji: newSelectedEmoji)
                    popover_state = .closed
                }
            }
    }
    
    func send_like(emoji: String) {
        let bar = make_actionbar_model(ev: event.id, damus: damus_state)
        guard let keypair = damus_state.keypair.to_full(),
              let like_ev = make_like_event(keypair: keypair, liked: event, content: emoji) else {
            return
        }

        bar.our_like = like_ev

        generator.impactOccurred()
        
        damus_state.postbox.send(like_ev)
    }
    
    var action_bar: some View {
        let bar = make_actionbar_model(ev: event.id, damus: damus_state)
        return HStack {
            if by_other_user {
                Spacer()
            }
            if !bar.is_empty {
                EventActionBar(damus_state: damus_state, event: event, bar: bar, options: [.no_spread, .hide_items_without_activity])
                    .padding(10)
                    .background(DamusColors.adaptableLighterGrey)
                    .disabled(true)
                    .cornerRadius(100)
                    .shadow(color: Color.black.opacity(0.05),radius: 3, y: 3)
                    .scaleEffect(0.7, anchor: .trailing)
            }
            if !by_other_user {
                Spacer()
            }
        }
        .padding(.top, -35)
        .padding(.horizontal, 10)
    }

    var body: some View {
        VStack {
            HStack(alignment: .bottom, spacing: 4) {
                if by_other_user {
                    self.profile_picture_view
                }
                
                self.event_bubble_wrapper
                    .background(
                        GeometryReader { geometry in
                            EmptyView()
                                .onAppear {
                                    let eventActionBarY = geometry.frame(in: .global).midY
                                    let screenMidY = UIScreen.main.bounds.midY
                                    self.isOnTopHalfOfScreen = eventActionBarY > screenMidY
                                }
                                .onChange(of: geometry.frame(in: .global).midY) { newY in
                                    let screenMidY = UIScreen.main.bounds.midY
                                    self.isOnTopHalfOfScreen = newY > screenMidY
                                }
                        }
                    )
                
                if !by_other_user {
                    self.profile_picture_view
                }
            }
            .contentShape(Rectangle())
            .id(event.id)
            .padding([.bottom], 6)
            
            self.action_bar
        }

    }
}

extension Notification.Name {
    static var toggle_thread_view: Notification.Name {
        return Notification.Name("convert_to_thread")
    }
}


func prev_reply_is_same(event: NostrEvent, prev_ev: NostrEvent?, replies: ReplyMap) -> NoteId? {
    if let prev = prev_ev {
        if let prev_reply_id = replies.lookup(prev.id) {
            if let cur_reply_id = replies.lookup(event.id) {
                if prev_reply_id != cur_reply_id {
                    return cur_reply_id.first
                }
            }
        }
    }
    return nil
}


func id_to_color(_ pubkey: Pubkey) -> Color {
    return Color(
        .sRGB,
        red: Double(pubkey.id[0]) / 255,
        green: Double(pubkey.id[1]) / 255,
        blue:  Double(pubkey.id[2]) / 255,
        opacity: 1
    )

}

#Preview {
    ChatView(event: test_note, selected_event: test_note, prev_ev: nil, next_ev: nil, damus_state: test_damus_state, thread: ThreadModel(event: test_note, damus_state: test_damus_state), scroll_to_event: nil, focus_event: nil, highlight_bubble: false, expand_reply: false)
}

#Preview {
    ChatView(event: test_short_note, selected_event: test_note, prev_ev: nil, next_ev: nil, damus_state: test_damus_state, thread: ThreadModel(event: test_note, damus_state: test_damus_state), scroll_to_event: nil, focus_event: nil, highlight_bubble: false, expand_reply: false)
}

#Preview {
    ChatView(event: test_short_note, selected_event: test_note, prev_ev: nil, next_ev: nil, damus_state: test_damus_state, thread: ThreadModel(event: test_note, damus_state: test_damus_state), scroll_to_event: nil, focus_event: nil, highlight_bubble: true, expand_reply: false)
}
