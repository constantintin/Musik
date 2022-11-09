//
//  PlaylistSelectorView.swift
//  Musik
//
//  Created by Constantin Loew on 25.07.21.
//

import Foundation
import SwiftUI
import SpotifyWebAPI
import SpotifyExampleContent
import Combine

class CurrentTrack: ObservableObject {
    @Published var track: Track
    init(_ track: Track) {
        self.track = track
    }
}

struct PlaylistSorterView: View {
    @EnvironmentObject var spotify: Spotify
    @State private var currentUser: SpotifyUser? = nil
    
    @StateObject private var currentTrack: CurrentTrack = CurrentTrack(.comeTogether)
    @State private var playlists: [Playlist<PlaylistItemsReference>] = []
    @State private var playlistViews: [PlaylistTrackSelectionView] = []
    
    @State private var trackBackgroundOpacity = 0.0
    
    @State private var cancellables: Set<AnyCancellable> = []
    
    @State private var isLoadingPlaylists = false
    @State private var couldntLoadPlaylists = false
    
    @State private var newPlaylistName: String = ""
    @FocusState private var newPlaylistFieldIsFocused: Bool
    
    @State private var alert: AlertItem? = nil
    
    init() { }
    
    /// Used only by the preview provider to provide sample data.
    fileprivate init(samplePlaylists: [Playlist<PlaylistItemsReference>]) {
        self._playlists = State(initialValue: samplePlaylists)
    }
    
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack {
            if playlists.isEmpty {
                if isLoadingPlaylists {
                    HStack {
                        ProgressView()
                            .padding()
                        Text("Loading Playlists")
                            .font(.title)
                            .foregroundColor(.secondary)
                    }
                }
                else if couldntLoadPlaylists {
                    Text("Couldn't Load Playlists")
                        .font(.title)
                        .foregroundColor(.secondary)
                }
                else {
                    Text("No Playlists Found")
                        .font(.title)
                        .foregroundColor(.secondary)
                }
            }
            else {
                HStack() {
                    TextField("New playlist's name", text: $newPlaylistName)
                        .focused($newPlaylistFieldIsFocused)
                        .padding(5)
                    Button(action: addPlaylist) {
                        Image(systemName: "plus.square")
                            .imageScale(Image.Scale.large)
                            .foregroundColor(Color.green)
                            .padding(5)
                    }
                }
                
                ScrollView(.vertical) {
                    LazyVGrid(columns: columns) {
                        ForEach(playlists, id: \.uri) { playlist in
                            PlaylistTrackSelectionView(spotify: spotify, playlist: playlist, current: currentTrack)
                        }
                    }
                    .padding(10)
                }
                TrackView(opacity: $trackBackgroundOpacity, track: $currentTrack.track)
                    .onTapGesture {
                        self.trackBackgroundOpacity = 1.0
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.trackBackgroundOpacity = 0.0
                        }
                        retrieveCurrentlyPlaying()
                    }
                    .padding(10)
            }
        }
        .navigationBarTitle("Sorter", displayMode: .inline)
        .navigationBarItems(trailing: refreshButton)
        .alert(item: $alert) { alert in
            Alert(title: alert.title, message: alert.message)
        }
        .onAppear(perform: retrieve)
    }

    var refreshButton: some View {
        Button(action: retrieve) {
            Image(systemName: "arrow.clockwise")
                .font(.title)
                .scaleEffect(0.8)
        }
        .disabled(isLoadingPlaylists)
        
    }
    
    func addPlaylist() {
        if let uri = currentUser?.uri {
            spotify.api.createPlaylist(for: uri,
                                          PlaylistDetails(name: newPlaylistName, isPublic: false, isCollaborative: nil, description: nil))
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { completion in
                    print("Getting user completion: \(completion)")
                }, receiveValue: { playlist in
                    var snapshot = playlist.snapshotId
                    if let uri = self.currentTrack.track.uri {
                        self.spotify.api.addToPlaylist(playlist.uri, uris: [uri], position: nil)
                            .receive(on: RunLoop.main)
                            .sink(
                                receiveCompletion: { completion in
                                    switch completion {
                                        case .finished:
                                            print("Added '\(self.currentTrack.track.name)' to '\(playlist.name)'")
                                        case .failure(let error):
                                            print("Adding to playlist failed with \(error)")
                                    }
                                },
                                receiveValue: { newSnapshot in
                                    snapshot = newSnapshot
                                }
                            ).store(in: &cancellables)
                    } else {
                        print("Current track \(self.currentTrack.track) has no uri")
                    }
                    let playlistWithReference = Playlist<PlaylistItemsReference>(
                        name: playlist.name,
                        items: PlaylistItemsReference(href: nil, total: 0),
                        owner: playlist.owner,
                        isPublic: playlist.isPublic,
                        isCollaborative: playlist.isCollaborative,
                        description: playlist.description,
                        snapshotId: snapshot,
                        externalURLs: playlist.externalURLs,
                        followers: playlist.followers,
                        href: playlist.href,
                        id: playlist.id,
                        uri: playlist.uri,
                        images: playlist.images
                    )
                    self.playlists.insert(playlistWithReference, at: 0)
                })
                .store(in: &cancellables)
        }
        self.newPlaylistFieldIsFocused = false
        self.newPlaylistName = ""
    }
    
    func retrieve() {
        retrieveCurrentlyPlaying()
        retrievePlaylists()
    }
    
    func retrieveCurrentlyPlaying() {
        spotify.api.currentPlayback()
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                print("Getting context completion: \(completion)")
            }, receiveValue: { context in
                switch context?.item {
                case let .some(.track(track)):
                    self.currentTrack.track = track
                default:
                    ()
                }
            })
            .store(in: &cancellables)
    }

    func retrievePlaylists() {
        
        // Don't try to load any playlists if we're in preview mode.
        if ProcessInfo.processInfo.isPreviewing { return }
        
        
        spotify.api.currentUserProfile()
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                print("Getting user completion: \(completion)")
            }, receiveValue: { user in
                currentUser = user
            })
            .store(in: &cancellables)
        
        self.isLoadingPlaylists = true
        self.playlists = []
        spotify.api.currentUserPlaylists()
            // Gets all pages of playlists.
            .extendPages(spotify.api)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoadingPlaylists = false
                    switch completion {
                        case .finished:
                            self.couldntLoadPlaylists = false
                        case .failure(let error):
                            self.couldntLoadPlaylists = true
                            self.alert = AlertItem(
                                title: "Couldn't Retrieve Playlists",
                                message: error.localizedDescription
                            )
                    }
                },
                // We will receive a value for each page of playlists. You could
                // use Combine's `collect()` operator to wait until all of the
                // pages have been retrieved.
                receiveValue: { playlistsPage in
                    let playlists = playlistsPage.items
                    for playlist in playlists {
                        if playlist.isCollaborative || playlist.owner?.uri == currentUser?.uri {
                            self.playlists.append(playlist)
                        }
                    }
                }
            )
            .store(in: &cancellables)

    }
}

struct PlaylistsSelectorView_Previews: PreviewProvider {

    static let spotify = Spotify()

    static let playlists: [Playlist<PlaylistItemsReference>] = [
        .menITrust, .modernPsychedelia, .menITrust,
        .lucyInTheSkyWithDiamonds, .rockClassics,
        .thisIsMFDoom, .thisIsSonicYouth, .thisIsMildHighClub,
        .thisIsSkinshape
    ]

    static var previews: some View {
        NavigationView {
            PlaylistSorterView(samplePlaylists: playlists)
                .environmentObject(spotify)
        }
    }
}
