//
//  URLConvertible+URLRequestConvertible.swift
//
//  Copyright (c) 2014-2018 Alamofire Software Foundation (http://alamofire.org/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

/// Types adopting the `URLConvertible` protocol can be used to construct `URL`s, which can then be used to construct
/// `URLRequests`.
public protocol URLConvertible
{
    func asURL() throws -> URL
}

extension String: URLConvertible
{
    public func asURL() throws -> URL
    {
        guard let url = URL(string: self) else { throw AFError.invalidURL(url: self) }
        return url
    }
}

extension URL: URLConvertible
{
    public func asURL() throws -> URL { self }
}

extension URLComponents: URLConvertible
{
    public func asURL() throws -> URL
    {
        guard let url = url else { throw AFError.invalidURL(url: self) }
        return url
    }
}

// MARK: -

// 可以转换成 urlrequest 的协议
public protocol URLRequestConvertible
{
    // 返回一个 urlrequest, 如果有错, 可以抛出异常
    func asURLRequest() throws -> URLRequest
}

// 创建 urlRequest
extension URLRequestConvertible
{
    
    public var urlRequest: URLRequest? { try? asURLRequest() }
}

// 返回自身
extension URLRequest: URLRequestConvertible
{
    public func asURLRequest() throws -> URLRequest { self }
}

// MARK: -

extension URLRequest {
    /// Creates an instance with the specified `url`, `method`, and `headers`.
    ///
    /// - Parameters:
    ///   - url:     The `URLConvertible` value.
    ///   - method:  The `HTTPMethod`.
    ///   - headers: The `HTTPHeaders`, `nil` by default.
    /// - Throws:    Any error thrown while converting the `URLConvertible` to a `URL`.
    public init(url: URLConvertible, method: HTTPMethod, headers: HTTPHeaders? = nil) throws {
        let url = try url.asURL()

        self.init(url: url)

        httpMethod = method.rawValue
        allHTTPHeaderFields = headers?.dictionary
    }
}
