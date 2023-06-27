//
//  RepostGroupView.swift
//  damus
//
//  Created by William Casarin on 2023-02-21.
//

import SwiftUI


enum EventGroupType {
    case repost(EventGroup)
    case reaction(EventGroup)
    case zap(ZapGroup)
    case profile_zap(ZapGroup)
    
    var is_note_zap: Bool {
        switch self {
        case .repost: return false
        case .reaction: return false
        case .zap: return true
        case .profile_zap: return false
        }
    }
    
    var zap_group: ZapGroup? {
        switch self {
        case .profile_zap(let grp):
            return grp
        case .zap(let grp):
            return grp
        case .reaction:
            return nil
        case .repost:
            return nil
        }
    }
    
    var events: [NostrEvent] {
        switch self {
        case .repost(let grp):
            return grp.events
        case .reaction(let grp):
            return grp.events
        case .zap(let zapgrp):
            return zapgrp.zap_requests()
        case .profile_zap(let zapgrp):
            return zapgrp.zap_requests()
        }
    }
}

enum ReactingTo {
    case your_note
    case tagged_in
    case your_profile
}

func determine_reacting_to(our_pubkey: String, ev: NostrEvent?) -> ReactingTo {
    guard let ev else {
        return .your_profile
    }
    
    if ev.pubkey == our_pubkey {
        return .your_note
    }
    
    return .tagged_in
}

func event_author_name(profiles: Profiles, pubkey: String) -> String {
    let alice_prof = profiles.lookup(id: pubkey)
    return Profile.displayName(profile: alice_prof, pubkey: pubkey).username.truncate(maxLength: 50)
}

func event_group_unique_pubkeys(profiles: Profiles, group: EventGroupType) -> [String] {
    var seen = Set<String>()
    var sorted = [String]()

    if let zapgrp = group.zap_group {
        let zaps = zapgrp.zaps

        for i in 0..<zaps.count {
            let zap = zapgrp.zaps[i]
            let pubkey: String

            if zap.is_anon {
                pubkey = ANON_PUBKEY
            } else {
                pubkey = zap.request.ev.pubkey
            }

            if !seen.contains(pubkey) {
                seen.insert(pubkey)
                sorted.append(pubkey)
            }
        }
    } else {
        let events = group.events

        for i in 0..<events.count {
            let ev = events[i]
            let pubkey = ev.pubkey
            if !seen.contains(pubkey) {
                seen.insert(pubkey)
                sorted.append(pubkey)
            }
        }
    }

    return sorted
}

/**
 Returns a notification string describing user actions in response to an event group type.

 The localization keys read by this function are the following (although some keys may not actually be used in practice):

 "??" - returned when there are no events associated with the specified event group type.

 "reacted_tagged_in_1" - returned when 1 reaction occurred to a post that the current user was tagged in
 "reacted_tagged_in_2" - returned when 2 reactions occurred to a post that the current user was tagged in
 "reacted_tagged_in_3" - returned when 3 or more reactions occurred to a post that the current user was tagged in
 "reacted_your_note_1" - returned when 1 reaction occurred to the current user's post
 "reacted_your_note_2" - returned when 2 reactions occurred to the current user's post
 "reacted_your_note_3" - returned when 3 or more reactions occurred to the current user's post
 "reacted_your_profile_1" - returned when 1 reaction occurred to the current user's profile
 "reacted_your_profile_2" - returned when 2 reactions occurred to the current user's profile
 "reacted_your_profile_3" - returned when 3 or more reactions occurred to the current user's profile

 "reposted_tagged_in_1" - returned when 1 repost occurred to a post that the current user was tagged in
 "reposted_tagged_in_2" - returned when 2 reposts occurred to a post that the current user was tagged in
 "reposted_tagged_in_3" - returned when 3 or more reposts occurred to a post that the current user was tagged in
 "reposted_your_note_1" - returned when 1 repost occurred to the current user's post
 "reposted_your_note_2" - returned when 2 reposts occurred to the current user's post
 "reposted_your_note_3" - returned when 3 or more reposts occurred to the current user's post
 "reposted_your_profile_1" - returned when 1 repost occurred to the current user's profile
 "reposted_your_profile_2" - returned when 2 reposts occurred to the current user's profile
 "reposted_your_profile_3" - returned when 3 or more reposts occurred to the current user's profile

 "zapped_tagged_in_1" - returned when 1 zap occurred to a post that the current user was tagged in
 "zapped_tagged_in_2" - returned when 2 zaps occurred to a post that the current user was tagged in
 "zapped_tagged_in_3" - returned when 3 or more zaps occurred to a post that the current user was tagged in
 "zapped_your_note_1" - returned when 1 zap occurred to the current user's post
 "zapped_your_note_2" - returned when 2 zaps occurred to the current user's post
 "zapped_your_note_3" - returned when 3 or more zaps occurred to the current user's post
 "zapped_your_profile_1" - returned when 1 zap occurred to the current user's profile
 "zapped_your_profile_2" - returned when 2 zaps occurred to the current user's profile
 "zapped_your_profile_3" - returned when 3 or more zaps occurred to the current user's profile
 */
func reacting_to_text(profiles: Profiles, our_pubkey: String, group: EventGroupType, ev: NostrEvent?, pubkeys: [String], locale: Locale? = nil) -> String {
    if group.events.count == 0 {
        return "??"
    }

    let verb = reacting_to_verb(group: group)
    let reacting_to = determine_reacting_to(our_pubkey: our_pubkey, ev: ev)
    let localization_key = "\(verb)_\(reacting_to)_\(min(pubkeys.count, 3))"
    let format = localizedStringFormat(key: localization_key, locale: locale)

    switch pubkeys.count {
    case 1:
        let display_name = event_author_name(profiles: profiles, pubkey: pubkeys[0])

        return String(format: format, locale: locale, display_name)
    case 2:
        let alice_name = event_author_name(profiles: profiles, pubkey: pubkeys[0])
        let bob_name = event_author_name(profiles: profiles, pubkey: pubkeys[1])

        return String(format: format, locale: locale, alice_name, bob_name)
    default:
        let alice_name = event_author_name(profiles: profiles, pubkey: pubkeys[0])
        let count = pubkeys.count - 1

        return String(format: format, locale: locale, count, alice_name)
    }
}

func reacting_to_verb(group: EventGroupType) -> String {
    switch group {
    case .reaction:
        return "reacted"
    case .repost:
        return "reposted"
    case .zap: fallthrough
    case .profile_zap:
        return "zapped"
    }
}

struct EventGroupView: View {
    let state: DamusState
    let event: NostrEvent?
    let group: EventGroupType
    
    func GroupDescription(_ pubkeys: [String]) -> some View {
        Text(verbatim: "\(reacting_to_text(profiles: state.profiles, our_pubkey: state.pubkey, group: group, ev: event, pubkeys: pubkeys))")
    }
    
    func ZapIcon(_ zapgrp: ZapGroup) -> some View {
        let fmt = format_msats_abbrev(zapgrp.msat_total)
        return VStack(alignment: .center) {
            Image("zap.fill")
                .foregroundColor(.orange)
            Text(verbatim: fmt)
                .foregroundColor(Color.orange)
        }
    }
    
    var GroupIcon: some View {
        Group {
            switch group {
            case .repost:
                Image("repost")
                    .foregroundColor(DamusColors.green)
            case .reaction:
                LINEAR_GRADIENT
                    .mask(Image("shaka.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    )
                    .frame(width: 20, height: 20)
            case .profile_zap(let zapgrp):
                ZapIcon(zapgrp)
            case .zap(let zapgrp):
                ZapIcon(zapgrp)
            }
        }
    }
    
    var body: some View {
        HStack(alignment: .top) {
            GroupIcon
                .frame(width: PFP_SIZE + 10)
            
            VStack(alignment: .leading) {
                let unique_pubkeys = event_group_unique_pubkeys(profiles: state.profiles, group: group)

                ProfilePicturesView(state: state, pubkeys: unique_pubkeys)
                
                if let event {
                    let thread = ThreadModel(event: event, damus_state: state)
                    let dest = ThreadView(state: state, thread: thread)
                    NavigationLink(destination: dest) {
                        VStack(alignment: .leading) {
                            GroupDescription(unique_pubkeys)
                            EventBody(damus_state: state, event: event, size: .normal, options: [.truncate_content])
                                .padding([.top], 1)
                                .padding([.trailing])
                                .foregroundColor(.gray)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    GroupDescription(unique_pubkeys)
                }
            }
        }
        .padding([.top], 6)
    }
}

let test_encoded_post = "{\"id\": \"8ba545ab96959fe0ce7db31bc10f3ac3aa5353bc4428dbf1e56a7be7062516db\",\"pubkey\": \"7e27509ccf1e297e1df164912a43406218f8bd80129424c3ef798ca3ef5c8444\",\"created_at\": 1677013417,\"kind\": 1,\"tags\": [],\"content\": \"hello\",\"sig\": \"93684f15eddf11f42afbdd81828ee9fc35350344d8650c78909099d776e9ad8d959cd5c4bff7045be3b0b255144add43d0feef97940794a1bc9c309791bebe4a\"}"
let test_repost_1 = NostrEvent(id: "", content: test_encoded_post, pubkey: "pk1", kind: 6, tags: [], createdAt: 1)
let test_repost_2 = NostrEvent(id: "", content: test_encoded_post, pubkey: "pk2", kind: 6, tags: [], createdAt: 1)
let test_reposts = [test_repost_1, test_repost_2]
let test_event_group = EventGroup(events: test_reposts)

struct EventGroupView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            EventGroupView(state: test_damus_state(), event: test_event, group: .repost(test_event_group))
                .frame(height: 200)
                .padding()
            
            EventGroupView(state: test_damus_state(), event: test_event, group: .reaction(test_event_group))
                .frame(height: 200)
                .padding()
        }
    }
    
}

