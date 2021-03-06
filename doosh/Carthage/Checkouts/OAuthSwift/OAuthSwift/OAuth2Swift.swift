//
//  OAuth2Swift.swift
//  OAuthSwift
//
//  Created by Dongri Jin on 6/22/14.
//  Copyright (c) 2014 Dongri Jin. All rights reserved.
//

import Foundation

public class OAuth2Swift: NSObject {
    
    public var client: OAuthSwiftClient
    public var version: OAuthSwiftCredential.Version { return self.client.credential.version }
    
    public var authorize_url_handler: OAuthSwiftURLHandlerType = OAuthSwiftOpenURLExternally.sharedInstance
    
    public var accessTokenBasicAuthentification = false
    
    var consumer_key: String
    var consumer_secret: String
    var authorize_url: String
    var access_token_url: String?
    var response_type: String
    var observer: AnyObject?
    var content_type: String?
    
    public convenience init(consumerKey: String, consumerSecret: String, authorizeUrl: String, accessTokenUrl: String, responseType: String){
        self.init(consumerKey: consumerKey, consumerSecret: consumerSecret, authorizeUrl: authorizeUrl, responseType: responseType)
        self.access_token_url = accessTokenUrl
    }
    
    public convenience init(consumerKey: String, consumerSecret: String, authorizeUrl: String, accessTokenUrl: String, responseType: String, contentType: String){
        self.init(consumerKey: consumerKey, consumerSecret: consumerSecret, authorizeUrl: authorizeUrl, responseType: responseType)
        self.access_token_url = accessTokenUrl
        self.content_type = contentType
    }
    
    public init(consumerKey: String, consumerSecret: String, authorizeUrl: String, responseType: String){
        self.consumer_key = consumerKey
        self.consumer_secret = consumerSecret
        self.authorize_url = authorizeUrl
        self.response_type = responseType
        self.client = OAuthSwiftClient(consumerKey: consumerKey, consumerSecret: consumerSecret)
        self.client.credential.version = .OAuth2
    }
    
    struct CallbackNotification {
        static let notificationName = "OAuthSwiftCallbackNotificationName"
        static let optionsURLKey = "OAuthSwiftCallbackNotificationOptionsURLKey"
    }
    
    struct OAuthSwiftError {
        static let domain = "OAuthSwiftErrorDomain"
        static let appOnlyAuthenticationErrorCode = 1
    }
    
    public typealias TokenSuccessHandler = (credential: OAuthSwiftCredential, response: NSURLResponse?, parameters: NSDictionary) -> Void
    public typealias FailureHandler = (error: NSError) -> Void
    
    
    public func authorizeWithCallbackURL(callbackURL: NSURL, scope: String, state: String, params: Dictionary<String, String> = Dictionary<String, String>(), success: TokenSuccessHandler, failure: ((error: NSError) -> Void)) {
        self.observer = NSNotificationCenter.defaultCenter().addObserverForName(CallbackNotification.notificationName, object: nil, queue: NSOperationQueue.mainQueue(), usingBlock:{
            notification in
            NSNotificationCenter.defaultCenter().removeObserver(self.observer!)
            let url = notification.userInfo![CallbackNotification.optionsURLKey] as! NSURL
            var responseParameters: Dictionary<String, String> = Dictionary()
            if let query = url.query {
                responseParameters += query.parametersFromQueryString()
            }
            if let fragment = url.fragment where !fragment.isEmpty {
                responseParameters += fragment.parametersFromQueryString()
            }
            if let accessToken = responseParameters["access_token"] {
                self.client.credential.oauth_token = accessToken
                success(credential: self.client.credential, response: nil, parameters: responseParameters)
            }
            else if let code = responseParameters["code"] {
                self.postOAuthAccessTokenWithRequestTokenByCode(code.safeStringByRemovingPercentEncoding,
                    callbackURL:callbackURL, success: success, failure: failure)
            }
            else if let error = responseParameters["error"], error_description = responseParameters["error_description"] {
                let errorInfo = [NSLocalizedFailureReasonErrorKey: NSLocalizedString(error, comment: error_description)]
                //failure(error: NSError(domain: OAuthSwiftErrorDomain, code: -1, userInfo: errorInfo))
            }
            else {
                let errorInfo = [NSStringEncodingErrorKey: "No access_token, no code and no error provided by server"]
                //failure(error: NSError(domain: OAuthSwiftErrorDomain, code: -1, userInfo: errorInfo))
            }
        })
        //let authorizeURL = NSURL(string: )
        var urlString = String()
        urlString += self.authorize_url
        urlString += (self.authorize_url.has("?") ? "&" : "?") + "client_id=\(self.consumer_key)"
        urlString += "&redirect_uri=\(callbackURL.absoluteString)"
        urlString += "&response_type=\(self.response_type)"
        if (scope != "") {
            urlString += "&scope=\(scope)"
        }
        if (state != "") {
            urlString += "&state=\(state)"
        }
        
        for param in params {
            urlString += "&\(param.0)=\(param.1)"
        }
        
        if let queryURL = NSURL(string: urlString) {
            self.authorize_url_handler.handle(queryURL)
        }
    }
    
    func postOAuthAccessTokenWithRequestTokenByCode(code: String, callbackURL: NSURL, success: TokenSuccessHandler, failure: FailureHandler?) {
        var parameters = Dictionary<String, AnyObject>()
        parameters["client_id"] = self.consumer_key
        parameters["client_secret"] = self.consumer_secret
        parameters["code"] = code
        parameters["grant_type"] = "authorization_code"
        parameters["redirect_uri"] = callbackURL.absoluteString.safeStringByRemovingPercentEncoding
        
        if self.content_type == "multipart/form-data" {
            self.client.postMultiPartRequest(self.access_token_url!, method: .POST, parameters: parameters, success: {
                data, response in
                let responseJSON: AnyObject? = try? NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableContainers)
                
                let responseParameters: NSDictionary
                
                if responseJSON != nil {
                    responseParameters = responseJSON as! NSDictionary
                } else {
                    let responseString = NSString(data: data, encoding: NSUTF8StringEncoding) as String!
                    responseParameters = responseString.parametersFromQueryString()
                }
                
                let accessToken = responseParameters["access_token"] as! String
                self.client.credential.oauth_token = accessToken
                success(credential: self.client.credential, response: response, parameters: responseParameters)
                }, failure: failure)
        } else {
            
            // special headers
            var headers: [String:String]? = nil
            if accessTokenBasicAuthentification {
                let authentification = "\(self.consumer_key):\(self.consumer_secret)".dataUsingEncoding(NSUTF8StringEncoding)
                if let base64Encoded = authentification?.base64EncodedStringWithOptions(NSDataBase64EncodingOptions(rawValue: 0))
                {
                    headers = ["Authorization": "Basic \(base64Encoded)"]
                }
            }
            
            self.client.request(self.access_token_url!, method: .POST, parameters: parameters, headers: headers, success: {
                data, response in
                let responseJSON: AnyObject? = try? NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableContainers)
                
                let responseParameters: NSDictionary
                
                if responseJSON != nil {
                    responseParameters = responseJSON as! NSDictionary
                } else {
                    let responseString = NSString(data: data, encoding: NSUTF8StringEncoding) as String!
                    responseParameters = responseString.parametersFromQueryString()
                }
                
                guard let accessToken = responseParameters["access_token"] as? String else {
                    if let failure = failure {
                        let errorInfo = [NSLocalizedFailureReasonErrorKey: NSLocalizedString("Could not get Access Token", comment: "Due to an error in the OAuth2 process, we couldn't get a valid token.")]
                        //failure(error: NSError(domain: OAuthSwiftErrorDomain, code: -1, userInfo: errorInfo))
                    }
                    return
                }
                self.client.credential.oauth_token = accessToken
                success(credential: self.client.credential, response: response, parameters: responseParameters)
                }, failure: failure)
        }
    }
    
    public class func handleOpenURL(url: NSURL) {
        let notification = NSNotification(name: CallbackNotification.notificationName, object: nil,
            userInfo: [CallbackNotification.optionsURLKey: url])
        NSNotificationCenter.defaultCenter().postNotification(notification)
    }
    
}