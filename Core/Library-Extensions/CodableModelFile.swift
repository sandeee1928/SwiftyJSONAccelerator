//
//  CodableModelFile.swift
//  SwiftyJSONAccelerator
//
//  Created by sakumar on 12/4/17.
//  Copyright © 2017 Karthikeya Udupa K M. All rights reserved.
//

import Foundation

struct CodableModelFile: ModelFile {
    
    var fileName: String
    var type: ConstructType
    var component: ModelComponent
    var sourceJSON: JSON
    var configuration: ModelGenerationConfiguration?
    var superClassName: String?
    
    // MARK: - Initialisers.
    init() {
        self.fileName = ""
        type = ConstructType.StructType
        component = ModelComponent.init()
        sourceJSON = JSON.init([])
    }
    
    mutating func setInfo(_ fileName: String, _ configuration: ModelGenerationConfiguration) {
        self.fileName = fileName
        type = configuration.constructType
        self.configuration = configuration
    }
    
    func moduleName() -> String {
        return "Codable"
    }
    
    func baseElementName() -> String? {
        guard let superClass = superClassName else { return nil }
        return NameGenerator.fixClassName(superClass, nil, false)
    }
    
    func mainBodyTemplateFileName() -> String {
        return "CodableTemplate"
    }
    
    mutating func generateAndAddComponentsFor(_ property: PropertyComponent) {
        switch property.propertyType {
        case .ValueType:
            component.stringConstants.append(genStringConstant(property.name, property.key))
            component.initialisers.append(genInitializerForVariable(property.name))
            component.declarations.append(genVariableDeclaration(property.name, property.type, property.isRequired, property.description))
            component.initParameters.append(genInitParameters(property.name, property.type, property.isRequired))
            component.decoders.append(genDecoder(property.name, property.type, property.isRequired, false))
            component.encoders.append(genEncoder(property.name, property.type, property.isRequired))
        case .ValueTypeArray:
            component.stringConstants.append(genStringConstant(property.name, property.key))
            component.initialisers.append(genInitializerForVariable(property.name))
            component.declarations.append(genVariableDeclaration(property.name, property.type, property.isRequired, property.description))
            component.initParameters.append(genInitParameters(property.name, property.type, property.isRequired))
            component.decoders.append(genDecoder(property.name, property.type, property.isRequired, true))
            component.encoders.append(genEncoder(property.name, property.type, property.isRequired))
        case .ObjectType:
            component.stringConstants.append(genStringConstant(property.name, property.key))
            component.initialisers.append(genInitializerForVariable(property.name))
            component.declarations.append(genVariableDeclaration(property.name, property.type, property.isRequired, property.description))
            component.initParameters.append(genInitParameters(property.name, property.type, property.isRequired))
            component.decoders.append(genDecoder(property.name, property.type, property.isRequired, false))
            component.encoders.append(genEncoder(property.name, property.type, property.isRequired))
        case .ObjectTypeArray:
            component.stringConstants.append(genStringConstant(property.name, property.key))
            component.initialisers.append(genInitializerForVariable(property.name))
            component.declarations.append(genVariableDeclaration(property.name, property.type, property.isRequired, property.description))
            component.initParameters.append(genInitParameters(property.name, property.type, property.isRequired))
            component.decoders.append(genDecoder(property.name, property.type, property.isRequired, true))
            component.encoders.append(genEncoder(property.name, property.type, property.isRequired))
        case .EmptyArray:
            component.stringConstants.append(genStringConstant(property.name, property.key))
            component.initialisers.append(genInitializerForVariable(property.name))
            component.declarations.append(genVariableDeclaration(property.name, "Any", property.isRequired, property.description))
            component.initParameters.append(genInitParameters(property.name, property.type, property.isRequired))
            component.decoders.append(genDecoder(property.name, "Any", property.isRequired, true))
            component.encoders.append(genEncoder(property.name, "Any", property.isRequired))
        case .NullType:
            // Currently we do not deal with null values.
            break
        }
    }
    
    // MARK: - Customised methods for SWiftyJSON
    // MARK: - Initialisers
    func genInitializerForVariable(_ name: String) -> String {
        return "self.\(name) = \(name)"
    }
    
    mutating func updateComponent(_ superInitParameters: [String]) {
        component.superInitParameters = superInitParameters
    }
    
}

extension CodableModelFile: DefaultModelFileComponent {
    func genStringConstant(_ constantName: String, _ value: String) -> String {
        //The incoming string is in the format "SeralizationKey.ConstantName" we only need the second part.
        let component = constantName.components(separatedBy: ".")
        return "case \(component.last!) = \"\(value)\""
    }
    
    func genVariableDeclaration(_ name: String, _ type: String, _ isRequired: Bool, _ description: String? = nil) -> String {
        let optionalString = isRequired ? "" : "?"
        var variable = "public var \(name): \(type)\(optionalString)"
        if let description = description {
            variable = "\(formatDescriotion("///\(description)"))\n" + variable
        }
        return variable
    }
    
    func formatDescriotion(_ description: String) -> String {
        let words = description.components(separatedBy: " ")
        var result = ""
        var multiplyer = 1
        for word in words {
            result += "\(word) "
            if result.count > 110 * multiplyer {
                result += "\n///"
                multiplyer += 1
            }
        }
        return result
    }
    
    func genInitParameters(_ name: String, _ type: String, _ isRequired: Bool) -> String {
        if isRequired {
            return "\(name): \(type)"
        } else {
            return "\(name): \(type)? = nil"
        }
    }
    
    func genEncoder(_ name: String, _ type: String, _ isRequired: Bool) -> String {
        let encodeString = isRequired ? "encode" : "encodeIfPresent"
       return "try container.\(encodeString)(\(name), forKey: .\(name))"
    }
    
    func genDecoder(_ name: String, _ type: String, _ isRequired: Bool, _ isArray: Bool) -> String {
        let decodeString = isRequired ? "decode" : "decodeIfPresent"
        return "\(name) = try values.\(decodeString)(\(type).self, forKey: .\(name))"
    }
}

