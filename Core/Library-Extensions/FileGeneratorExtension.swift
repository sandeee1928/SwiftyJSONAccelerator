//
//  FileGenerator.swift
//  SwiftyJSONAccelerator
//
//  Created by Karthik on 27/12/2016.
//  Copyright © 2016 Karthikeya Udupa K M. All rights reserved.
//

import Foundation

extension FileGenerator {

    static func generateFileContentWith(_ modelFile: ModelFile, configuration: ModelGenerationConfiguration) -> String {

        var content = loadFileWith("BaseTemplate")
        let singleTab = "  ", doubleTab = "    "
        content = content.replacingOccurrences(of: "{OBJECT_NAME}", with: modelFile.fileName)
        content = content.replacingOccurrences(of: "{DATE}", with: todayDateString())
        content = content.replacingOccurrences(of: "{OBJECT_KIND}", with: modelFile.type.rawValue)
        
        if modelFile.component.declarations.count > 0 {
            content = content.replacingOccurrences(of: "{JSON_PARSER_LIBRARY_BODY}", with: loadFileWith(modelFile.mainBodyTemplateFileName()))
        } else {
            content = content.replacingOccurrences(of: "{JSON_PARSER_LIBRARY_BODY}", with: "")
        }
        

        if modelFile.type == .ClassType {
            content = content.replacingOccurrences(of: "{REQUIRED}", with: " required ")
        } else {
            content = content.replacingOccurrences(of: "{REQUIRED}", with: " ")
        }
        if let authorName = configuration.authorName {
            content = content.replacingOccurrences(of: "__NAME__", with: authorName)
        }
        if let companyName = configuration.companyName {
            content = content.replacingOccurrences(of: "__MyCompanyName__", with: companyName)
        }
        if configuration.isFinalRequired && configuration.jsonType == .json {
            content = content.replacingOccurrences(of: "{INCLUDE_HEADER}", with: "\nimport \(modelFile.moduleName())")
        } else {
            content = content.replacingOccurrences(of: "{INCLUDE_HEADER}", with: "")
        }

        var classesExtendFrom: [String] = []
        if let extendFrom = modelFile.baseElementName() {
            classesExtendFrom = [extendFrom]
        } else if configuration.jsonType == .jsonSchema {
            classesExtendFrom = classesExtendFrom + ["Codable"]
        }
        
        if configuration.supportNSCoding && configuration.constructType == .ClassType && configuration.jsonType == .json {
            classesExtendFrom = classesExtendFrom + ["NSCoding"]
        }

        if configuration.isFinalRequired && configuration.constructType == .ClassType {
            content = content.replacingOccurrences(of: "{IS_FINAL}", with: " final ")
        } else {
            content = content.replacingOccurrences(of: "{IS_FINAL}", with: " ")
        }

        if classesExtendFrom.count > 0 {
            content = content.replacingOccurrences(of: "{EXTEND_FROM}", with: classesExtendFrom.joined(separator: ", "))
            content = content.replacingOccurrences(of: "{EXTENDED_OBJECT_COLON}", with: ": ")
        } else {
            content = content.replacingOccurrences(of: "{EXTEND_FROM}", with: "")
            content = content.replacingOccurrences(of: "{EXTENDED_OBJECT_COLON}", with: "")
        }

        var sortedDeclarations = modelFile.component.declarations.sorted { return ($0 < $1) }
        sortedDeclarations.sort { (!$0.contains("?") && $1.contains("?")) }
        var sortedInitialisers = modelFile.component.initialisers.sorted { return $0 < $1 }
        sortedInitialisers.sort { (!$0.contains("?") && $1.contains("?")) }
        var sortedDescription = modelFile.component.description.sorted { return $0 < $1 }
        sortedDescription.sort { (!$0.contains("?") && $1.contains("?")) }
        var sortedInitParameters = modelFile.component.initParameters.sorted { return $0 < $1 }
        sortedInitParameters.sort { return !$0.contains("?") && $1.contains("?") }
        var sortedSuperInitParameters = modelFile.component.superInitParameters.sorted { return $0 < $1 }
        sortedSuperInitParameters.sort { return !$0.contains("?") && $1.contains("?") }
        
        var sortedAllInitParameters = (sortedSuperInitParameters + sortedInitParameters).sorted { return $0 < $1 }
        sortedAllInitParameters.sort { return !$0.contains("?") && $1.contains("?") }
        
        
        let declarations = sortedDeclarations.map({ doubleTab + $0 }).joined(separator: "\n\(doubleTab)")
        let initialisers = sortedInitialisers.map({ doubleTab + $0 }).joined(separator: "\n\(doubleTab)")
        let description = sortedDescription.map({ doubleTab + $0 }).joined(separator: "\n\(doubleTab)")
        let allInitParameters = sortedAllInitParameters.map({ $0 }).joined(separator: ",\n")
        
        let formatedSuperInitPrams = sortedSuperInitParameters.map({ $0.components(separatedBy: ":").first! + ": " + $0.components(separatedBy: ":").first! }).joined(separator: ",\n")
        let superInitCall = (modelFile.baseElementName() == nil) ? "" : "super.init(\(formatedSuperInitPrams))"
        
            
        
        content = content.replacingOccurrences(of: "{DECLARATION}", with: declarations)
        content = content.replacingOccurrences(of: "{INITIALIZER}", with: initialisers)
        content = content.replacingOccurrences(of: "{SUPER_INIT}", with: initialisers)
        content = content.replacingOccurrences(of: "{DESCRIPTION}", with: description)
        content = content.replacingOccurrences(of: "{INIT_PARAMETERS}", with: allInitParameters)
        content = content.replacingOccurrences(of: "{SUPER_INIT_CALL}", with: superInitCall)

        if configuration.constructType == .StructType {
            content = content.replacingOccurrences(of: " convenience", with: "")
        }

        if configuration.supportNSCoding && configuration.constructType == .ClassType && modelFile.component.declarations.count > 0 {
            let codingTemplate = (configuration.jsonType == .json) ? "NSCodingTemplate" : "EncodableDecodableTemplate"
            content = content.replacingOccurrences(of: "{NSCODING_SUPPORT}", with: loadFileWith(codingTemplate))
            let encoders = modelFile.component.encoders.map({ doubleTab + $0 }).joined(separator: "\n")
            let decoders = modelFile.component.decoders.map({ doubleTab + $0 }).joined(separator: "\n")
            content = content.replacingOccurrences(of: "{DECODERS}", with: decoders)
            content = content.replacingOccurrences(of: "{ENCODERS}", with: encoders)
    
            let overrideValue = (modelFile.baseElementName() == nil) ? " " : " override "
            content = content.replacingOccurrences(of: "{OVERRIDE}", with: overrideValue)
            let superInit = (modelFile.baseElementName() == nil) ? "" : """
            do {
                try super.init(from: decoder)
            }
            """
            content = content.replacingOccurrences(of: "{DECODERS_SUPER_INIT_CALL}", with: superInit)
            
            let sortedStringConstants = modelFile.component.stringConstants.sorted { return $0 < $1 }
            let stringConstants = sortedStringConstants.map({ doubleTab + $0 }).joined(separator: "\n\(doubleTab)")
            content = content.replacingOccurrences(of: "{STRING_CONSTANT}", with: stringConstants)
        } else {
            content = content.replacingOccurrences(of: "{NSCODING_SUPPORT}", with: "")
        }

        return content
    }

    /**
     Write the given content to a file at the mentioned path.
     
     - parameter name:      The name of the file.
     - parameter content:   Content that has to be written on the file.
     - parameter path:      Path where the file has to be created.
     
     - returns: Boolean indicating if the process was successful.
     */
    static internal func writeToFileWith(_ name: String, content: String, path: String) throws {
        let filename = path.appendingFormat("%@", (name + ".swift"))
        try FileManager.default.createDirectory(at: URL.init(fileURLWithPath: path),
                                                withIntermediateDirectories: true,
                                                attributes: nil)
        try content.write(toFile: filename, atomically: true, encoding: String.Encoding.utf8)
        
    }

    static fileprivate func todayDateString() -> String {
        let formatter = DateFormatter.init()
        formatter.dateStyle = .short
        return formatter.string(from: Date.init())
    }
    
    static internal func indent(files: [String], at directoryPath: String, completionHandler:( (Bool) -> Void )? = nil) {
        let taskQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.background)
        taskQueue.async {
            let launchPath = "/usr/local/bin/swiftformat"
            let buildTask = Process()
            buildTask.launchPath = launchPath
            buildTask.arguments = files
            buildTask.currentDirectoryPath = directoryPath
            buildTask.terminationHandler = { task in
                DispatchQueue.main.async(execute: {
                    if let completionHandler = completionHandler {
                        completionHandler(true)
                    }
                })
            }
            buildTask.launch()
            buildTask.waitUntilExit()
        }
    }
}
