//
//  ParameterEncoding.swift
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

// 参数字典
public typealias Parameters = [String: Any]

// 一个定义如何编码的协议
public protocol ParameterEncoding
{
    func encode(_ urlRequest: URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest
}
 
// 生成一个使用url-encoded方式编码过的字符串，可以添加到url或是请求体中，至于使用何种方式取决于编码的目的地参数
// http 头中的 Content-Type 字段会被设置为 application/x-www-form-urlencoded; charset=utf-8
// 由于没有一个明确的规定如何编码一个集合，我们在这里约定，对于数组，我们会在名字后面加上一个中括号[] 如(foo[]=1&foo[]=2)，对于字典 则在中括号中再加入键值，如foo[bar]=baz
public struct URLEncoding: ParameterEncoding
{
    // 辅助类型：定义编码后的字符串是放到url还是请求体中
    public enum Destination
    {
        // 对于 .get、.head、.delete 请求，它会将已编码查询字符串应用到现有的查询字符串中；对于其他类型的请求，会将其设置为 HTTP body
        case methodDependent
        // 将编码字符串设置或追加到请求的 URL 中
        case queryString
        // 将编码字符串设置为 URLRequest 的 HTTP body。
        case httpBody

        // 是否将编码字符串放到url中
        func encodesParametersInURL(for method: HTTPMethod) -> Bool
        {
            switch self
            {
            case .methodDependent: return [.get, .head, .delete].contains(method)
            case .queryString: return true
            case .httpBody: return false
            }
        }
    }

    /// Configures how `Array` parameters are encoded.
    public enum ArrayEncoding {
        /// An empty set of square brackets is appended to the key for every value. This is the default behavior.
        case brackets
        /// No brackets are appended. The key is encoded as is.
        case noBrackets

        func encode(key: String) -> String {
            switch self {
            case .brackets:
                return "\(key)[]"
            case .noBrackets:
                return key
            }
        }
    }

    /// Configures how `Bool` parameters are encoded.
    public enum BoolEncoding {
        /// Encode `true` as `1` and `false` as `0`. This is the default behavior.
        case numeric
        /// Encode `true` and `false` as string literals.
        case literal

        func encode(value: Bool) -> String {
            switch self {
            case .numeric:
                return value ? "1" : "0"
            case .literal:
                return value ? "true" : "false"
            }
        }
    }

    // MARK: Properties

    /// Returns a default `URLEncoding` instance with a `.methodDependent` destination.
    public static var `default`: URLEncoding { URLEncoding() }

    /// Returns a `URLEncoding` instance with a `.queryString` destination.
    public static var queryString: URLEncoding { URLEncoding(destination: .queryString) }

    /// Returns a `URLEncoding` instance with an `.httpBody` destination.
    public static var httpBody: URLEncoding { URLEncoding(destination: .httpBody) }

    /// The destination defining where the encoded query string is to be applied to the URL request.
    public let destination: Destination

    /// The encoding to use for `Array` parameters.
    public let arrayEncoding: ArrayEncoding

    /// The encoding to use for `Bool` parameters.
    public let boolEncoding: BoolEncoding

    // MARK: Initialization

    /// Creates an instance using the specified parameters.
    ///
    /// - Parameters:
    ///   - destination:   `Destination` defining where the encoded query string will be applied. `.methodDependent` by
    ///                    default.
    ///   - arrayEncoding: `ArrayEncoding` to use. `.brackets` by default.
    ///   - boolEncoding:  `BoolEncoding` to use. `.numeric` by default.
    public init(destination: Destination = .methodDependent,
                arrayEncoding: ArrayEncoding = .brackets,
                boolEncoding: BoolEncoding = .numeric) {
        self.destination = destination
        self.arrayEncoding = arrayEncoding
        self.boolEncoding = boolEncoding
    }

    // MARK: Encoding
    // ParameterEncoding 协议的实现：编码并设置 request对象
    public func encode(_ urlRequest: URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest
    {
        // 获取 request
        var urlRequest = try urlRequest.asURLRequest()
        // 获取参数，如果没有参数，那么直接返回
        guard let parameters = parameters else { return urlRequest }

        // 获取请求方法，同时根据请求方法来判断是否需要编码参数到 url 中
        if let method = urlRequest.method, destination.encodesParametersInURL(for: method)// 直接编码到 url 中
        {
            // 获取 url
            guard let url = urlRequest.url else
            {
                throw AFError.parameterEncodingFailed(reason: .missingURL)
            }

            // 构建一个URLComponents对象，并在其中添加参数
            if var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false), !parameters.isEmpty
            {
                // 此处 map 是 optional 的map，如果 optionvalue 不为空，则会调用 map 内的闭包
                // 如果 url 中本来就有一部分参数了，那么就将新的参数附加在后面
                let percentEncodedQuery = (urlComponents.percentEncodedQuery.map { $0 + "&" } ?? "") + query(parameters)
                urlComponents.percentEncodedQuery = percentEncodedQuery
                urlRequest.url = urlComponents.url
            }
        }
        else// 这里是要添加到请求体中
        {
            // 如果请求头尚未设置 Content-Type
            if urlRequest.headers["Content-Type"] == nil
            {
                // 在请求头中设置编码格式
                urlRequest.headers.update(.contentType("application/x-www-form-urlencoded; charset=utf-8"))
            }
            // 编码到请求体中
            urlRequest.httpBody = Data(query(parameters).utf8)
        }

        return urlRequest
    }

    // 创建一个使用百分号转义urlencode编码的键和值的方法
    public func queryComponents(fromKey key: String, value: Any) -> [(String, String)]
    {
        // 最终结果
        var components: [(String, String)] = []
        
        switch value
        {
        // 如果value依然是字典，那么键后面加上[key]再调用自身，也就是做递归处理
        case let dictionary as [String: Any]:
            for (nestedKey, value) in dictionary
            {
                components += queryComponents(fromKey: "\(key)[\(nestedKey)]", value: value)
            }
        // 如果value是数组，通过遍历在键后面加上[]后依然调用自身
        // 把数组拼接到url中的规则是这样的：数组["a", "b", "c"]拼接后的结果是key[]="a"&key[]="b"&key[]="c"
        case let array as [Any]:
            for value in array
            {
                components += queryComponents(fromKey: arrayEncoding.encode(key: key), value: value)
            }
        // 如果value是NSNumber，要进一步判断这个NSNumber是不是表示布尔类型
        case let number as NSNumber:
            if number.isBool// bool 值的处理
            {
                components.append((escape(key), escape(boolEncoding.encode(value: number.boolValue))))
            }
            else
            {
                components.append((escape(key), escape("\(number)")))
            }
        // 如果value是Bool，转义后直接拼接进数组
        case let bool as Bool:
            components.append((escape(key), escape(boolEncoding.encode(value: bool))))
        // 其他情况，转义后直接拼接进数组
        default:
            components.append((escape(key), escape("\(value)")))
        }
        return components
    }

    // 上边函数中的key已经是字符串类型了，那么为什么还要进行转义的？
    // 这是因为在url中有些字符是不允许的，这些字符会干扰url的解析
    // :#[]@!$&'()*+,;= 这些字符必须要做转义 ?和/可以不用转义
    // 转义的意思就是百分号编码
    public func escape(_ string: String) -> String
    {
        // 使用了系统自带的函数来进行百分号编码
        string.addingPercentEncoding(withAllowedCharacters: .afURLQueryAllowed) ?? string
    }

    // 将参数编码为查询字符串
    // 可以看到URLEncoding方式是将parameters通过添加 & ，= 的方式拼接到url身后
    private func query(_ parameters: [String: Any]) -> String
    {
        // 创建一个数组，这个数组中存放的是元组数据，元组中存放的是key和字符串类型的value
        var components: [(String, String)] = []

        // 遍历参数，对参数做进一步的处理，然后拼接到数组中
        for key in parameters.keys.sorted(by: <)
        {
            let value = parameters[key]!
            // key的类型是String，但value的类型是any
            // 也就是说value不一定是字符串，也有可能是数组或字典，因此针对value需要做进一步的处理
            components += queryComponents(fromKey: key, value: value)
        }
        // 把元组内部的数据用=号拼接，然后用符号&把数组拼接成字符串
        return components.map { "\($0)=\($1)" }.joined(separator: "&")
    }
}

// 使用 json 编码参数
public struct JSONEncoding: ParameterEncoding
{
    // MARK: Properties

    // 使用默认参数构造
    public static var `default`: JSONEncoding { JSONEncoding() }

    // 让其拥有更好的展示效果
    public static var prettyPrinted: JSONEncoding { JSONEncoding(options: .prettyPrinted) }

    // JSON序列化的写入方式
    public let options: JSONSerialization.WritingOptions
    public init(options: JSONSerialization.WritingOptions = [])
    {
        self.options = options
    }

    // MARK: Encoding

    // ParameterEncoding 协议实现
    public func encode(_ urlRequest: URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest
    {
        var urlRequest = try urlRequest.asURLRequest()

        guard let parameters = parameters else { return urlRequest }

        do
        {
            // json 格式化数据
            let data = try JSONSerialization.data(withJSONObject: parameters, options: options)

            // 如果 Content-Type 尚未设置
            if urlRequest.headers["Content-Type"] == nil
            {
                // 设置请求头的Content-Type
                urlRequest.headers.update(.contentType("application/json"))
            }
            // 加上请求体
            urlRequest.httpBody = data
        }
        catch
        {
            throw AFError.parameterEncodingFailed(reason: .jsonEncodingFailed(error: error))
        }

        return urlRequest
    }

    // 实现同上一致, 不过这个可以接受数组的 json
    public func encode(_ urlRequest: URLRequestConvertible, withJSONObject jsonObject: Any? = nil) throws -> URLRequest
    {
        var urlRequest = try urlRequest.asURLRequest()

        guard let jsonObject = jsonObject else { return urlRequest }

        do
        {
            let data = try JSONSerialization.data(withJSONObject: jsonObject, options: options)

            if urlRequest.headers["Content-Type"] == nil {
                urlRequest.headers.update(.contentType("application/json"))
            }

            urlRequest.httpBody = data
        }
        catch
        {
            throw AFError.parameterEncodingFailed(reason: .jsonEncodingFailed(error: error))
        }

        return urlRequest
    }
}

// MARK: -

extension NSNumber {
    fileprivate var isBool: Bool {
        // Use Obj-C type encoding to check whether the underlying type is a `Bool`, as it's guaranteed as part of
        // swift-corelibs-foundation, per [this discussion on the Swift forums](https://forums.swift.org/t/alamofire-on-linux-possible-but-not-release-ready/34553/22).
        String(cString: objCType) == "c"
    }
}



