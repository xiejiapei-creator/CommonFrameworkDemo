//
//  ViewController.swift
//  AlamofireSourceCodeAnalysis
//
//  Created by 谢佳培 on 2021/1/22.
//

import UIKit
import Alamofire

class ViewController: UIViewController
{

    override func viewDidLoad()
    {
        super .viewDidLoad()
     
        // 请求网络
        //requestNetwork()
        
        // 核心流程
        //coreProcess()
        
        // 底层
        //basement()
        
        // 安全策略
        //serverTrust()
        
        // 响应
        response()
    }
    
    // 请求网络
    func requestNetwork()
    {
        let urlString = "https://www.baidu.com"

        AF.request(urlString).response
        { (response) in
            debugPrint(response)
        }
    }
    
    // 核心流程
    func coreProcess()
    {
        // 淘宝的一个搜索api
        let url = "http://suggest.taobao.com/sug"
        // 对袜子进行搜索
        let parameters: [String: Any] = [
            "code" : "utf-8",
            "q" : "袜子"
        ]

        AF.request(url, method: .get, parameters: parameters)
            .validate(statusCode: [201])
            .responseData(queue: DispatchQueue.global())
            { (responseData) in
                switch responseData.result
                {
                case .success(let data):
                  guard let jsonString = String(data: data, encoding: .utf8) else { return }
                  print("json字符串：\(jsonString)")
                case .failure(let error):
                  print("错误信息：\(error)")
                }
            }
    }
    
    // 底层
    func basement()
    {
        let parameterErrorReason = AFError.ParameterEncodingFailureReason.missingURL
        print(parameterErrorReason)
    }

    // 安全策略
    func serverTrust()
    {
        let manager = ServerTrustManager(evaluators: ["httpbin.org": PinnedCertificatesTrustEvaluator()])
        let managerSession = Session(serverTrustManager: manager)
        managerSession.request("https://httpbin.org/get").responseJSON
        { response in
            debugPrint(response)
        }
    }
    
    // 响应
    func response()
    {
        AF.request("https://httpbin.org/get")
            .responseString
            { response in
                print("Response String: \(String(describing: response.value))")
            }
            .responseJSON
            { response in
                print("Response JSON: \(String(describing: response.value))")
            }
    }
}



 






