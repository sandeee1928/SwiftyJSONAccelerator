//
//  SJModelGenerator.swift
//  SwiftyJSONAccelerator
//
//  Created by Karthik on 20/10/2015.
//  Copyright © 2015 Karthikeya Udupa K M. All rights reserved.
//

import Foundation

/// Model generator responsible for creation of models based on the JSON, needs to be initialised
/// with all properties before proceeding.
public struct ModelGenerator {

    /// Configuration for generation of the model.
    var configuration: ModelGenerationConfiguration
    /// JSON content that has to be processed.
    var baseContent: JSON

    /**
   Initialise the structure with the JSON and configuration

   - parameter baseContent:   Base content JSON that has to be used to generate the model.
   - parameter configuration: Configuration to generate the the model.
   */
    init(_ baseContent: JSON, _ configuration: ModelGenerationConfiguration) {
        self.baseContent = baseContent
        self.configuration = configuration
    }

    /**
   Generate the models for the structure based on the set configuration and content.
   - returns: An array of files that were generated.
   */
    mutating func generate() -> [ModelFile] {
        if configuration.jsonType == .jsonSchema {
            configuration.modelMappingLibrary = .Codable
            return self.generateModelForJSON2(baseContent, getFileName(form: baseContent), true, fileUrl: configuration.jsonFileURL!)
        } else {
            return self.generateModelForJSON(baseContent, configuration.baseClassName, true)
        }
    }

    /**
   Generate a set model files for the given JSON object.

   - parameter object:           Object that has to be parsed.
   - parameter defaultClassName: Default Classname for the object.
   - parameter isTopLevelObject: Is the current object the root object in the JSON.

   - returns: Model files for the current object and sub objects.
   */
    func generateModelForJSON(_ object: JSON, _ defaultClassName: String, _ isTopLevelObject: Bool) -> [ModelFile] {

        let className = NameGenerator.fixClassName(defaultClassName, self.configuration.prefix, isTopLevelObject)
        var modelFiles: [ModelFile] = []
        
        

        // Incase the object was NOT a dictionary. (this would only happen in case of the top level
        // object, since internal objects are handled within the function and do not pass an array here)
        if let rootObject = object.array, let firstObject = rootObject.first {
            let subClassType = firstObject.detailedValueType()
            // If the type of the first item is an object then make it the base class and generate
            // stuff. However, currently it does not make a base file to handle the array.
            if subClassType == .Object {
                return self.generateModelForJSON(JSONHelper.reduce(rootObject), defaultClassName, isTopLevelObject)
            }
            return []
        }
        
        if let rootObject = object.dictionary {
            // A model file to store the current model.
            var currentModel = self.initialiseModelFileFor(configuration.modelMappingLibrary)
            currentModel.setInfo(className, configuration)
            currentModel.sourceJSON = object

            for (key, value) in rootObject {
                /// basic information, name, type and the constant to store the key.
                let variableName = NameGenerator.fixVariableName(key)
                let variableType = value.detailedValueType()
                let stringConstantName = NameGenerator.variableKey(className, variableName)
                
                switch variableType {
                case .Array:
                    if value.arrayValue.count <= 0 {
                        currentModel.generateAndAddComponentsFor(PropertyComponent.init(variableName, VariableType.Array.rawValue, stringConstantName, key, .EmptyArray))
                    } else {
                        let subClassType = value.arrayValue.first!.detailedValueType()
                        if subClassType == .Object {
                            let models = generateModelForJSON(JSONHelper.reduce(value.arrayValue), variableName, false)
                            modelFiles = modelFiles + models
                            let model = models.first
                            let classname = model?.fileName
                            currentModel.generateAndAddComponentsFor(PropertyComponent.init(variableName, classname!, stringConstantName, key, .ObjectTypeArray))
                        } else {
                            currentModel.generateAndAddComponentsFor(PropertyComponent.init(variableName, subClassType.rawValue, stringConstantName, key, .ValueTypeArray))
                        }
                    }
                case .Object:
                    let models = generateModelForJSON(value, variableName, false)
                    let model = models.first
                    let typeName = model?.fileName
                    currentModel.generateAndAddComponentsFor(PropertyComponent.init(variableName, typeName!, stringConstantName, key, .ObjectType))
                    modelFiles = modelFiles + models
                case .Null:
                    currentModel.generateAndAddComponentsFor(PropertyComponent.init(variableName, VariableType.Null.rawValue, stringConstantName, key, .NullType))
                    break
                default:
                    currentModel.generateAndAddComponentsFor(PropertyComponent.init(variableName, variableType.rawValue, stringConstantName, key, .ValueType))
                } 
            }

            modelFiles = [currentModel] + modelFiles
        }

        // at the end we return the collection of files.
        return modelFiles
    }
    
    func getFileName(form json: JSON) -> String {
        if let fileName = json["javaType"].string?.components(separatedBy: ".").last {
            return fileName
        } else {
            return ""
        }
    }
    
    mutating func generateModelForJSON2(_ object: JSON, _ defaultClassName: String, _ isTopLevelObject: Bool, fileUrl: URL) -> [ModelFile] {
        let className = NameGenerator.fixClassName(defaultClassName, self.configuration.prefix, isTopLevelObject)
        let filePathUrl = configuration.jsonFileURL
        var modelFiles: [ModelFile] = []
        if let rootObject = object.dictionary {
            var currentModel = self.initialiseModelFileFor(configuration.modelMappingLibrary)
            currentModel.setInfo(className, configuration)
            currentModel.sourceJSON = object
            currentModel.description = rootObject["description"]?.string
            var superInitPrams = [String]()
            if let extends = rootObject["extends"]?["$ref"].string,
                let extendsJSON = getJSON(from: extends, with: fileUrl.absoluteString) {
                let models = generateModelForJSON2(extendsJSON.0, getFileName(form: extendsJSON.0), false, fileUrl: extendsJSON.1)
                modelFiles = modelFiles + models
                if let model = models.last {
                    currentModel.superClassName = model.fileName
                    superInitPrams += (model.component.initParameters + model.component.superInitParameters)
                }
                configuration.jsonFileURL = filePathUrl
            }
            
            if let properties = rootObject["properties"]?.dictionary {
                for (key, value) in properties {
                    
                    let variableName = NameGenerator.fixVariableName(key)
                    
                    let dataType = value["type"].string ?? "object"
                    var objectName = NameGenerator.fixClassName(variableName, "", false)
                    
                    if let _ = value["properties"].dictionary {
                        let models = generateModelForJSON2(value, variableName, false, fileUrl: fileUrl)
                        modelFiles = modelFiles + models
                    } else if let ref = value["$ref"].string, let extendsJSON = getJSON(from: ref, with: fileUrl.absoluteString) {
                        let models = generateModelForJSON2(extendsJSON.0, getFileName(form: extendsJSON.0), false, fileUrl: extendsJSON.1)
                        modelFiles = modelFiles + models
                        if let model = models.last {
                            objectName = model.fileName
                        }
                        configuration.jsonFileURL = filePathUrl
                    }

                    let variableType = getDetailedValueType(dataType)
                    let isRequired = value["required"].bool ?? false
                    let propertyType: PropertyType = (variableType == .Object) ? .ObjectType : .ValueType
                    
                    var type = variableType.rawValue
                    switch variableType {
                    case .Array:
                        if let items = value["items"].dictionary {
                            if let ref = items["$ref"]?.string, let extendsJSON = getJSON(from: ref, with: fileUrl.absoluteString) {
                                let models = generateModelForJSON2(extendsJSON.0, getFileName(form: extendsJSON.0), false, fileUrl: extendsJSON.1)
                                modelFiles = modelFiles + models
                                if let model = models.last {
                                    type = "[\(model.fileName)]"
                                }
                            } else {
                                let dataType = items["type"]?.string ?? "object"
                                type = "[\(getDetailedValueType(dataType))]"
                            }
                        }
                    case .Object:
                        type = objectName
                    default:
                        type = variableType.rawValue
                    }
                    let propertyComponent = PropertyComponent(variableName, type,
                                                          "",
                                                          key,
                                                          propertyType,
                                                          isRequired,
                                                          value["description"].string,
                                                          value["$ref"].string)
                    currentModel.generateAndAddComponentsFor(propertyComponent)
                }
            }
            currentModel.updateComponent(superInitPrams)
            modelFiles += [currentModel]
        }
        return modelFiles
    }
    
    func getDetailedValueType(_ type: String) -> VariableType {
        switch type.lowercased() {
        case "string":
            return VariableType.String
        case "boolean", "bool":
            return VariableType.Bool
        case "int", "long", "integer":
            return VariableType.Int
        case "double", "number":
            return VariableType.Double
        case "float":
            return VariableType.Float
        case "array":
            return VariableType.Array
        default:
            return VariableType.Object
        }
    }
    
    mutating func getJSON(fromFile: String, updateJsonFileURL: Bool = true) -> JSON? {
        var newFilePath = ""
        if fromFile.contains("classpath:") {
            newFilePath = fromFile.replacingOccurrences(of: "classpath:",
                                                               with: "/Users/sakumar/Documents/Workspace/SourceCode/D3_Collector_Api/d3_collector_api/d3_api_base/src/main/resources")
            newFilePath = URL(fileURLWithPath: newFilePath).absoluteString
        } else {
            let paths = fromFile.components(separatedBy: "/")
            let sss = paths.filter { (strig) -> Bool in
                return strig == ".."
            }
            guard var currentPath = configuration.jsonFileURL?.absoluteString.components(separatedBy: "/") else {
                print("File note found ===========>>>>>>>>>>>>>> \(fromFile)")
                return nil
            }
            for _ in 0...sss.count {
                currentPath.removeLast()
            }
            currentPath += paths[sss.count..<paths.count]
            newFilePath = currentPath.joined(separator: "/")
        }
        if let url = URL(string: newFilePath) {
            
            guard let jsonData = try? Data(contentsOf: url), let jsonString = String(data: jsonData, encoding: .utf8) else {
                print("File note found ===========>>>>>>>>>>>>>> \(fromFile)")
                return nil
            }
            if updateJsonFileURL || fromFile.contains("classpath:") {
                configuration.updateJsonFileURL(url: url)
            }
            
            if let object = JSONHelper.convertToObject(jsonString).1 {
                return JSON(object)
            }
        }
        
        print("File note found ===========>>>>>>>>>>>>>> \(fromFile)")
        return nil
    }
    
    mutating func getJSON(from filePath: String, with relativePath: String) -> (JSON, URL)? {
        var newFilePath = ""
        if filePath.contains("classpath:") {
            newFilePath = filePath.replacingOccurrences(of: "classpath:",
                                                        with: "/Users/sakumar/Documents/Workspace/SourceCode/D3_Collector_Api/d3_collector_api/d3_api_base/src/main/resources")
            newFilePath = URL(fileURLWithPath: newFilePath).absoluteString
        } else {
            //            var updateFilePath = filePath
            let paths = filePath.components(separatedBy: "/")
            let sss = paths.filter { (strig) -> Bool in
                return strig == ".."
            }
            var currentPath = relativePath.components(separatedBy: "/")
            for _ in 0...sss.count {
                currentPath.removeLast()
            }
            currentPath += paths[sss.count..<paths.count]
            newFilePath = currentPath.joined(separator: "/")
        }
        if let url = URL(string: newFilePath) {
            
            guard let jsonData = try? Data(contentsOf: url), let jsonString = String(data: jsonData, encoding: .utf8) else {
                print("File note found ===========>>>>>>>>>>>>>> \(filePath)")
                return nil
            }
            
            if let object = JSONHelper.convertToObject(jsonString).1 {
                return (JSON(object), url)
            }
        }
        
        print("File note found ===========>>>>>>>>>>>>>> \(filePath)")
        return nil
    }

    /**
   Generates the notification message for the model files returned.

   - parameter modelFiles: Array of model files that were generated.

   - returns: Notification tht was generated.
   */
    func generateNotificationFor(_ modelFiles: [ModelFile]) -> NSUserNotification {
        let notification: NSUserNotification = NSUserNotification()
        notification.title = NSLocalizedString("SwiftyJSONAccelerator", comment: "")
        if modelFiles.count > 0 {
            let firstModel = (modelFiles.first)!
            notification.subtitle = String.init(format: NSLocalizedString("Completed - %@.swift", comment: ""), firstModel.fileName)
        } else {
            notification.subtitle = NSLocalizedString("No files were generated, cannot model arrays inside arrays.", comment: "")
        }
        return notification
    }

    /**
   Initialise a ModelFile of a certain Library type based on the requirement.

   - parameter modelMappingLibrary: Library the generated modal has to support.

   - returns: A new model file of the required type.
   */
    func initialiseModelFileFor(_ modelMappingLibrary: JSONMappingLibrary) -> ModelFile {
        switch modelMappingLibrary {
        case .ObjectMapper:
            return ObjectMapperModelFile()
        case .SwiftyJSON:
            return SwiftyJSONModelFile()
        case .Marshal:
            return MarshalModelFile()
        case .Codable:
            return CodableModelFile()
        }
    }
}
