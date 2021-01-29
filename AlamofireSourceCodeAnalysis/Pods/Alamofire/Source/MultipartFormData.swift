//
//  MultipartFormData.swift
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

#if os(iOS) || os(watchOS) || os(tvOS)
import MobileCoreServices
#elseif os(macOS)
import CoreServices
#endif

//
open class MultipartFormData
{
    // MARK: - Helper Types

    // 换行回车：对"\r\n"的一个封装
    enum EncodingCharacters
    {
        static let crlf = "\r\n"
    }

    // 边界生产者
    enum BoundaryGenerator
    {
        // 设计一个枚举来封装边界类型
        enum BoundaryType
        {
            case initial, encapsulated, final
        }

        // 生成边界字符串
        static func randomBoundary() -> String
        {
            let first = UInt32.random(in: UInt32.min...UInt32.max)
            let second = UInt32.random(in: UInt32.min...UInt32.max)

            return String(format: "alamofire.boundary.%08x%08x", first, second)
        }

        // 转换函数
        static func boundaryData(forBoundaryType boundaryType: BoundaryType, boundary: String) -> Data
        {
            let boundaryText: String

            switch boundaryType
            {
            case .initial:
                boundaryText = "--\(boundary)\(EncodingCharacters.crlf)"
            case .encapsulated:
                boundaryText = "\(EncodingCharacters.crlf)--\(boundary)\(EncodingCharacters.crlf)"
            case .final:
                boundaryText = "\(EncodingCharacters.crlf)--\(boundary)--\(EncodingCharacters.crlf)"
            }

            return Data(boundaryText.utf8)
        }
    }

    // 对每一个body部分的描述，这个类只能在MultipartFormData内部访问，外部无法访问
    class BodyPart
    {
        let headers: HTTPHeaders //对数据的描述
        let bodyStream: InputStream //数据来源，Alamofire中使用InputStream统一进行处理
        let bodyContentLength: UInt64 //该数据的大小
        var hasInitialBoundary = false //是否包含初始边界
        var hasFinalBoundary = false //是否包含结束边界

        init(headers: HTTPHeaders, bodyStream: InputStream, bodyContentLength: UInt64)
        {
            self.headers = headers
            self.bodyStream = bodyStream
            self.bodyContentLength = bodyContentLength
        }
    }

    // MARK: - Properties

    /// Default memory threshold used when encoding `MultipartFormData`, in bytes.
    public static let encodingMemoryThreshold: UInt64 = 10_000_000

    // 通过Content-Type来说明当前数据的类型为multipart/form-data，这样服务器就知道客户端将要发送的数据是多表单了
    open lazy var contentType: String = "multipart/form-data; boundary=\(self.boundary)"

    // 获取数据的大小，该属性是一个计算属性
    public var contentLength: UInt64 { bodyParts.reduce(0) { $0 + $1.bodyContentLength } }

    // 表示边界，在初始化中会使用BoundaryGenerator来生成一个边界字符串
    public let boundary: String

    let fileManager: FileManager

    // 是一个集合，包含了每一个数据的封装对象BodyPart
    private var bodyParts: [BodyPart]
    private var bodyPartError: AFError?
    // 设置stream传输的buffer大小
    private let streamBufferSize: Int

    // MARK: - Lifecycle

    // 初始化方法
    public init(fileManager: FileManager = .default, boundary: String? = nil)
    {
        self.fileManager = fileManager
        self.boundary = boundary ?? BoundaryGenerator.randomBoundary()
        bodyParts = []
        streamBufferSize = 1024
    }

    // MARK: - Body Parts

    // 传入的数据是个Data类型
    public func append(_ data: Data, withName name: String, fileName: String? = nil, mimeType: String? = nil)
    {
        let headers = contentHeaders(withName: name, fileName: fileName, mimeType: mimeType)
        let stream = InputStream(data: data)
        let length = UInt64(data.count)

        append(stream, withLength: length, headers: headers)
    }

    /// Creates a body part from the file and appends it to the instance.
    ///
    /// The body part data will be encoded using the following format:
    ///
    /// - `Content-Disposition: form-data; name=#{name}; filename=#{generated filename}` (HTTP Header)
    /// - `Content-Type: #{generated mimeType}` (HTTP Header)
    /// - Encoded file data
    /// - Multipart form boundary
    ///
    /// The filename in the `Content-Disposition` HTTP header is generated from the last path component of the
    /// `fileURL`. The `Content-Type` HTTP header MIME type is generated by mapping the `fileURL` extension to the
    /// system associated MIME type.
    ///
    /// - Parameters:
    ///   - fileURL: `URL` of the file whose content will be encoded into the instance.
    ///   - name:    Name to associate with the file content in the `Content-Disposition` HTTP header.
    public func append(_ fileURL: URL, withName name: String) {
        let fileName = fileURL.lastPathComponent
        let pathExtension = fileURL.pathExtension

        if !fileName.isEmpty && !pathExtension.isEmpty {
            let mime = mimeType(forPathExtension: pathExtension)
            append(fileURL, withName: name, fileName: fileName, mimeType: mime)
        } else {
            setBodyPartError(withReason: .bodyPartFilenameInvalid(in: fileURL))
        }
    }

    // 包含最多参数的函数，这个函数会成为其他函数的内部实现基础
    public func append(_ fileURL: URL, withName name: String, fileName: String, mimeType: String)
    {
        // 根据name，mimeType，fileName计算出headers
        let headers = contentHeaders(withName: name, fileName: fileName, mimeType: mimeType)

        //============================================================
        //                 Check 1 - is file URL?
        //============================================================

        // 判断fileURL是不是一个file的URL
        guard fileURL.isFileURL else
        {
            setBodyPartError(withReason: .bodyPartURLInvalid(url: fileURL))
            return
        }

        //============================================================
        //              Check 2 - is file URL reachable?
        //============================================================

        // 判断该fileURL是不是可达的
        do
        {
            let isReachable = try fileURL.checkPromisedItemIsReachable()
            guard isReachable else
            {
                setBodyPartError(withReason: .bodyPartFileNotReachable(at: fileURL))
                return
            }
        }
        catch
        {
            setBodyPartError(withReason: .bodyPartFileNotReachableWithError(atURL: fileURL, error: error))
            return
        }

        //============================================================
        //            Check 3 - is file URL a directory?
        //============================================================

        // 判断fileURL是不是一个文件夹，而不是具体的数据
        var isDirectory: ObjCBool = false
        let path = fileURL.path

        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue else
        {
            setBodyPartError(withReason: .bodyPartFileIsDirectory(at: fileURL))
            return
        }

        //============================================================
        //          Check 4 - can the file size be extracted?
        //============================================================

        // 判断fileURL指定的文件能不能被读取
        let bodyContentLength: UInt64

        do
        {
            guard let fileSize = try fileManager.attributesOfItem(atPath: path)[.size] as? NSNumber else
            {
                setBodyPartError(withReason: .bodyPartFileSizeNotAvailable(at: fileURL))
                return
            }

            bodyContentLength = fileSize.uint64Value
        }
        catch
        {
            setBodyPartError(withReason: .bodyPartFileSizeQueryFailedWithError(forURL: fileURL, error: error))
            return
        }

        //============================================================
        //       Check 5 - can a stream be created from file URL?
        //============================================================

        // 判断能不能通过fileURL创建InputStream
        guard let stream = InputStream(url: fileURL) else
        {
            setBodyPartError(withReason: .bodyPartInputStreamCreationFailed(for: fileURL))
            return
        }

        append(stream, withLength: bodyContentLength, headers: headers)
    }

    /// Creates a body part from the stream and appends it to the instance.
    ///
    /// The body part data will be encoded using the following format:
    ///
    /// - `Content-Disposition: form-data; name=#{name}; filename=#{filename}` (HTTP Header)
    /// - `Content-Type: #{mimeType}` (HTTP Header)
    /// - Encoded stream data
    /// - Multipart form boundary
    ///
    /// - Parameters:
    ///   - stream:   `InputStream` to encode into the instance.
    ///   - length:   Length, in bytes, of the stream.
    ///   - name:     Name to associate with the stream content in the `Content-Disposition` HTTP header.
    ///   - fileName: Filename to associate with the stream content in the `Content-Disposition` HTTP header.
    ///   - mimeType: MIME type to associate with the stream content in the `Content-Type` HTTP header.
    public func append(_ stream: InputStream,
                       withLength length: UInt64,
                       name: String,
                       fileName: String,
                       mimeType: String) {
        let headers = contentHeaders(withName: name, fileName: fileName, mimeType: mimeType)
        append(stream, withLength: length, headers: headers)
    }

    // 设计函数来实现把每一条数据封装成BodyPart对象，然后拼接到bodyParts数组中
    public func append(_ stream: InputStream, withLength length: UInt64, headers: HTTPHeaders)
    {
        // 给出headers，stream和length就能生成BodyPart对象
        let bodyPart = BodyPart(headers: headers, bodyStream: stream, bodyContentLength: length)
        // 然后把它拼接到数组中就行了
        bodyParts.append(bodyPart)
    }

    // MARK: - Data Encoding

    // 编码整个请求体
    public func encode() throws -> Data
    {
        // 如果发生异常, 则直接抛出
        if let bodyPartError = bodyPartError
        {
            throw bodyPartError
        }

        // 最终的请求体
        var encoded = Data()

        // 给数组中第一个数据设置开始边界，最后一个数据设置结束边界
        bodyParts.first?.hasInitialBoundary = true
        bodyParts.last?.hasFinalBoundary = true

        // 拼接 body
        for bodyPart in bodyParts
        {
            // 编码内容块
            let encodedData = try encode(bodyPart)
            // 把bodyPart对象转换成Data类型，然后拼接到encoded中
            encoded.append(encodedData)
        }

        return encoded
    }

    // 写入编码好的数据到指定文件（处理大尺寸数据）
    public func writeEncodedData(to fileURL: URL) throws
    {
        if let bodyPartError = bodyPartError
        {
            throw bodyPartError
        }

        // 判断写入文件是否已存在
        if fileManager.fileExists(atPath: fileURL.path)
        {
            throw AFError.multipartEncodingFailed(reason: .outputStreamFileAlreadyExists(at: fileURL))
        }
        // 判断是否是文件 url
        else if !fileURL.isFileURL
        {
            throw AFError.multipartEncodingFailed(reason: .outputStreamURLInvalid(url: fileURL))
        }

        // 生成流
        guard let outputStream = OutputStream(url: fileURL, append: false) else
        {
            throw AFError.multipartEncodingFailed(reason: .outputStreamCreationFailed(for: fileURL))
        }
        
        // 开启流
        outputStream.open()
        // defer可以定义代码块结束后执行的语句
        defer { outputStream.close() }

        // 设置头尾
        bodyParts.first?.hasInitialBoundary = true
        bodyParts.last?.hasFinalBoundary = true

        for bodyPart in bodyParts
        {
            // 写入
            try write(bodyPart, to: outputStream)
        }
    }

    // MARK: - Private - Body Part Encoding

    // 编码内容块为 data
    private func encode(_ bodyPart: BodyPart) throws -> Data
    {
        // 最终数据
        var encoded = Data()

        // 如果是第一个数据， 要使用起始字段, 否则用正常分割字段
        let initialData = bodyPart.hasInitialBoundary ? initialBoundaryData() : encapsulatedBoundaryData()
        encoded.append(initialData)

        // 添加头字段
        let headerData = encodeHeaders(for: bodyPart)
        encoded.append(headerData)

        // 添加内容字段
        let bodyStreamData = try encodeBodyStream(for: bodyPart)
        encoded.append(bodyStreamData)

        // 如果是最后一个数据，要加上尾字段
        if bodyPart.hasFinalBoundary
        {
            encoded.append(finalBoundaryData())
        }

        return encoded
    }

    private func encodeHeaders(for bodyPart: BodyPart) -> Data {
        let headerText = bodyPart.headers.map { "\($0.name): \($0.value)\(EncodingCharacters.crlf)" }
            .joined()
            + EncodingCharacters.crlf

        return Data(headerText.utf8)
    }

    private func encodeBodyStream(for bodyPart: BodyPart) throws -> Data {
        let inputStream = bodyPart.bodyStream
        inputStream.open()
        defer { inputStream.close() }

        var encoded = Data()

        while inputStream.hasBytesAvailable {
            var buffer = [UInt8](repeating: 0, count: streamBufferSize)
            let bytesRead = inputStream.read(&buffer, maxLength: streamBufferSize)

            if let error = inputStream.streamError {
                throw AFError.multipartEncodingFailed(reason: .inputStreamReadFailed(error: error))
            }

            if bytesRead > 0 {
                encoded.append(buffer, count: bytesRead)
            } else {
                break
            }
        }

        return encoded
    }

    // MARK: - Private - Writing Body Part to Output Stream

    private func write(_ bodyPart: BodyPart, to outputStream: OutputStream) throws {
        try writeInitialBoundaryData(for: bodyPart, to: outputStream)
        try writeHeaderData(for: bodyPart, to: outputStream)
        try writeBodyStream(for: bodyPart, to: outputStream)
        try writeFinalBoundaryData(for: bodyPart, to: outputStream)
    }

    private func writeInitialBoundaryData(for bodyPart: BodyPart, to outputStream: OutputStream) throws {
        let initialData = bodyPart.hasInitialBoundary ? initialBoundaryData() : encapsulatedBoundaryData()
        return try write(initialData, to: outputStream)
    }

    private func writeHeaderData(for bodyPart: BodyPart, to outputStream: OutputStream) throws {
        let headerData = encodeHeaders(for: bodyPart)
        return try write(headerData, to: outputStream)
    }

    private func writeBodyStream(for bodyPart: BodyPart, to outputStream: OutputStream) throws {
        let inputStream = bodyPart.bodyStream

        inputStream.open()
        defer { inputStream.close() }

        while inputStream.hasBytesAvailable {
            var buffer = [UInt8](repeating: 0, count: streamBufferSize)
            let bytesRead = inputStream.read(&buffer, maxLength: streamBufferSize)

            if let streamError = inputStream.streamError {
                throw AFError.multipartEncodingFailed(reason: .inputStreamReadFailed(error: streamError))
            }

            if bytesRead > 0 {
                if buffer.count != bytesRead {
                    buffer = Array(buffer[0..<bytesRead])
                }

                try write(&buffer, to: outputStream)
            } else {
                break
            }
        }
    }

    private func writeFinalBoundaryData(for bodyPart: BodyPart, to outputStream: OutputStream) throws {
        if bodyPart.hasFinalBoundary {
            return try write(finalBoundaryData(), to: outputStream)
        }
    }

    // MARK: - Private - Writing Buffered Data to Output Stream

    private func write(_ data: Data, to outputStream: OutputStream) throws {
        var buffer = [UInt8](repeating: 0, count: data.count)
        data.copyBytes(to: &buffer, count: data.count)

        return try write(&buffer, to: outputStream)
    }

    private func write(_ buffer: inout [UInt8], to outputStream: OutputStream) throws {
        var bytesToWrite = buffer.count

        while bytesToWrite > 0, outputStream.hasSpaceAvailable {
            let bytesWritten = outputStream.write(buffer, maxLength: bytesToWrite)

            if let error = outputStream.streamError {
                throw AFError.multipartEncodingFailed(reason: .outputStreamWriteFailed(error: error))
            }

            bytesToWrite -= bytesWritten

            if bytesToWrite > 0 {
                buffer = Array(buffer[bytesWritten..<buffer.count])
            }
        }
    }

    // MARK: - Private - Mime Type

    private func mimeType(forPathExtension pathExtension: String) -> String {
        if
            let id = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension as CFString, nil)?.takeRetainedValue(),
            let contentType = UTTypeCopyPreferredTagWithClass(id, kUTTagClassMIMEType)?.takeRetainedValue() {
            return contentType as String
        }

        return "application/octet-stream"
    }

    // MARK: - Private - Content Headers

    private func contentHeaders(withName name: String, fileName: String? = nil, mimeType: String? = nil) -> HTTPHeaders {
        var disposition = "form-data; name=\"\(name)\""
        if let fileName = fileName { disposition += "; filename=\"\(fileName)\"" }

        var headers: HTTPHeaders = [.contentDisposition(disposition)]
        if let mimeType = mimeType { headers.add(.contentType(mimeType)) }

        return headers
    }

    // MARK: - Private - Boundary Encoding

    private func initialBoundaryData() -> Data {
        BoundaryGenerator.boundaryData(forBoundaryType: .initial, boundary: boundary)
    }

    private func encapsulatedBoundaryData() -> Data {
        BoundaryGenerator.boundaryData(forBoundaryType: .encapsulated, boundary: boundary)
    }

    private func finalBoundaryData() -> Data {
        BoundaryGenerator.boundaryData(forBoundaryType: .final, boundary: boundary)
    }

    // MARK: - Private - Errors

    private func setBodyPartError(withReason reason: AFError.MultipartEncodingFailureReason) {
        guard bodyPartError == nil else { return }
        bodyPartError = AFError.multipartEncodingFailed(reason: reason)
    }
}

 
 





