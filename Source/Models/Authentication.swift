//
//  AuthenticationViewModel.swift
//  Anxia
//
//  Created by Bryan Veloso on 6/20/20.
//  Copyright © 2020 Avalonstar Inc. All rights reserved.
//

import Foundation
import Combine
import OAuthSwift
import Alamofire

let TWITTER_URL_SCHEME = "anxia"

struct RequestOAuthTokenResponse: Decodable {
    let oauthToken: String
    let oauthTokenSecret: String
    let oauthCallbackConfirmed: String
}

struct RequestAccessTokenResponse: Decodable {
  let oauthToken: String
  let oauthTokenSecret: String
  let userId: String
  let screenName: String
}

final class Authentication: ObservableObject {
    @Published var authUrl: URL? { willSet { self.objectWillChange.send(self) } }
    @Published var credential: RequestAccessTokenResponse? { willSet { self.objectWillChange.send(self) } }
    @Published var loggedIn: Bool = false { willSet { self.objectWillChange.send(self) } }
    @Published var showSheet: Bool = false { willSet { self.objectWillChange.send(self) } }
    
    let objectWillChange = PassthroughSubject<Authentication, Never>()
    
    var callbackObserver: Any? {
        willSet {
            // We will add and remove this observer on an as-needed basis.
            guard let token = callbackObserver else { return }
            NotificationCenter.default.removeObserver(token)
        }
    }
        
    private var accessToken: String?
    private var handle: OAuthSwiftRequestHandle?
    private var oauthswift = OAuth1Swift(
        consumerKey: Constants.API.consumerKey,
        consumerSecret: Constants.API.consumerSecret,
        requestTokenUrl: Constants.API.requestTokenUrl,
        authorizeUrl: Constants.API.authorizeUrl,
        accessTokenUrl: Constants.API.accessTokenUrl
    )
    
    func getRequestToken(_ complete: @escaping (RequestOAuthTokenResponse) -> Void) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let parameters = ["callback_url": "\(TWITTER_URL_SCHEME)://"]
        AF.request("https://proxy.anxia.app/auth/request_token", parameters: parameters).validate().responseDecodable(of: RequestOAuthTokenResponse.self, decoder: decoder) { response in
            switch response.result {
            case .success:
                complete(response.value!)
            case let .failure(error):
                print(error)
            }
        }
    }
    
    func getAccessToken(parameters: [String: String], _ complete: @escaping (RequestAccessTokenResponse) -> Void) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        AF.request("https://proxy.anxia.app/auth/access_token", parameters: parameters).validate().responseDecodable(of: RequestAccessTokenResponse.self, decoder: decoder) { response in
            debugPrint(response)
        }
    }
        
    func authenticate() {
        self.showSheet = true
        self.getRequestToken() { requestResponse in
            // Listening for the user login callback.
            self.callbackObserver = NotificationCenter.default.addObserver(forName: .twitterCallback, object: nil, queue: .main) { notification in
                self.callbackObserver = nil
                self.showSheet = false
                self.authUrl = nil
                guard let url = notification.object as? URL else { return }
                guard let verifier = url.value(forParameter: "oauth_verifier") else { return }
                let input = [
                    "oauth_token": requestResponse.oauthToken,
                    "oauth_verifier": verifier
                ]
                self.getAccessToken(parameters: input) { accessResponse in
                    self.authUrl = nil
                    self.credential = accessResponse
                    self.loggedIn = true
                }
            }
            
            // Step 2: Open up the login sheet.
            let urlString = "https://api.twitter.com/oauth/authenticate?oauth_token=\(requestResponse.oauthToken)"
            guard let oauthUrl = URL(string: urlString) else { return }
            DispatchQueue.main.async {
                self.authUrl = oauthUrl
            }
        }
    }
        
    func logout() {
        self.credential = nil
        self.loggedIn = false
    }
}

extension Notification.Name {
    static let twitterCallback = Notification.Name(rawValue: "Twitter.CallbackNotification.Name")
}

extension URL {
    func value(forParameter name: String) -> String? {
        guard let urlComponents = URLComponents(url: self, resolvingAgainstBaseURL: false), let queryItems = urlComponents.queryItems else { return nil }
        let items = queryItems.filter { $0.name == name }
        return items.first?.value
    }
}
