//
//  SJEditorViewController.swift
//  SwiftyJSONAccelerator
//
//  Created by Karthik on 16/10/2015.
//  Copyright © 2015 Karthikeya Udupa K M. All rights reserved.
//

import Cocoa

fileprivate func < <T: Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l < r
    case (nil, _?):
        return true
    default:
        return false
    }
}

fileprivate func <= <T: Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l <= r
    default:
        return !(rhs < lhs)
    }
}

/// View for the processing of the content and generation of the files.
class SJEditorViewController: NSViewController, NSTextViewDelegate {

    // MARK: Outlet files.
    @IBOutlet var textView: SJTextView!
    @IBOutlet var messageLabel: NSTextField!
    @IBOutlet var errorImageView: NSImageView!
    @IBOutlet var baseClassTextField: NSTextField!
    @IBOutlet var prefixClassTextField: NSTextField!
    @IBOutlet var companyNameTextField: NSTextField!
    @IBOutlet var authorNameTextField: NSTextField!
    @IBOutlet var includeHeaderImportCheckbox: NSButton!
    @IBOutlet var enableNSCodingSupportCheckbox: NSButton!
    @IBOutlet var setAsFinalCheckbox: NSButton!
    @IBOutlet var librarySelector: NSPopUpButton!
    @IBOutlet var modelTypeSelectorSegment: NSSegmentedControl!
    @IBOutlet var jsonTypeSelectorSegment: NSSegmentedControl!
    var jsonFilePath: URL?
    var destinationFilePathUrl: URL?
    
    @IBOutlet weak var mappingCheckbox: NSButton!
    // MARK: View methods
    override func loadView() {
        super.loadView()
        textView!.delegate = self
        textView!.updateFormat()
        textView!.lnv_setUpLineNumberView()
        resetErrorImage()
        authorNameTextField?.stringValue = NSFullUserName()
        jsonTypeSelectorSegment.selectedSegment = 1
        let year = Calendar.current.component(.year, from: Date())
        companyNameTextField.stringValue = "\(year) T-Mobile"
        setAsFinalCheckbox.state = 0
    }

    // MARK: Actions
    @IBAction func format(_ sender: AnyObject?) {
        let fileUrl = self.jsonFilePath
        var generatedFiles = [String]()
        
        guard let destinationPathUrl = openFile() else { return }
        destinationFilePathUrl = destinationPathUrl
        let destinationPath = getDestinationPath(form: destinationPathUrl)
        FileGenerator.deleteOldFiles(at: destinationPath)
        if validateAndFormat(true) {
            let object: AnyObject? = JSONHelper.convertToObject(textView?.string).1
            if mappingCheckbox.state == 1 {
                guard let object = object  else { return }
                let json = JSON(object)
                guard let jsonArray = json.array  else { return }
                for tempJson in jsonArray {
                    if let mappingList = tempJson["event_type_mapping"].array {
                        for mapping in mappingList {
                            if let schemaPath = mapping["schema_path"].string, let eventType = mapping["event_type"].string {
                                if eventType.contains("analytics") || eventType.contains("observability.zipkin") {
                                    if let dirPath = fileUrl?.deletingLastPathComponent() {
                                        // this is for d3_schema
//                                        let filePath = "\(dirPath.relativePath)/schemas/\(schemaPath)"
                                       let filePath = "\(dirPath.relativePath)/\(schemaPath)"
                                        generatedFiles += generateModel(at: filePath, destinationPath: destinationPath)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                if let filePath = fileUrl?.relativePath {
                    generatedFiles = generateModel(at: filePath, destinationPath: destinationPath)
                } else {
                    generatedFiles = generateModel(destinationPath: destinationPath)
                }
            }
            let generatedFileSet = Set(generatedFiles.map { "\(destinationPath)/\($0).swift" })
            if destinationPathUrl.lastPathComponent.contains(".xcodeproj") {
                FileGenerator.addFileToXcodeProject(at: destinationPathUrl, files: Array(generatedFileSet))
            }
            for file in Array(generatedFileSet) {
                print(file)
            }
            notify(fileCount: Array(generatedFileSet).count)
        }
    }
    
    private func getDestinationPath(form pathUrl: URL) -> String {
        if pathUrl.lastPathComponent.contains(".xcodeproj") {
            let actualPath = pathUrl.deletingLastPathComponent()
            let targetName = pathUrl.lastPathComponent.components(separatedBy: ".").first!
            return "\(actualPath.path)/\(targetName)/Analytics/Public/SchemaModels"
        } else {
            return "\(pathUrl.path)/Public/SchemaModels"
        }
    }

    @IBAction func handleMultipleFiles(_ sender: AnyObject?) {
        let folderPath = openFile()
        // No file path was selected, go back!
        guard let path = folderPath?.path else { return }

        do {
            let generatedModelInfo = try MultipleModelGenerator.generate(forPath: path)
            for file in generatedModelInfo.modelFiles {
                let content = FileGenerator.generateFileContentWith(file, configuration: generatedModelInfo.configuration)
                let name = file.fileName
                try FileGenerator.writeToFileWith(name, content: content, path: generatedModelInfo.configuration.filePath)
            }
            notify(fileCount: generatedModelInfo.modelFiles.count)

        } catch let error as MultipleModelGeneratorError {
            let alert: NSAlert = NSAlert()
            alert.messageText = "Unable to generate the files."
            alert.informativeText = error.errorMessage()
            alert.runModal()
        } catch let error as NSError {
            let alert: NSAlert = NSAlert()
            alert.messageText = "Unable to generate the files."
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /**
   Validates and updates the textview.

   - parameter pretty: If the JSON is to be pretty printed.

   - returns: if the format was valid.
   */
    func validateAndFormat(_ pretty: Bool) -> Bool {

        if textView?.string?.count == 0 {
            return false
        }

        textView!.updateFormat()
        let (valid, error): (Bool, NSError?) = JSONHelper.isStringValidJSON(textView?.string)
        if valid {
            if pretty {
                textView?.string = JSONHelper.prettyJSON(textView?.string)!
                textView!.lnv_textDidChange(Notification.init(name: NSNotification.Name.NSTextDidChange, object: nil))
                return true
            }
            correctJSONMessage()
        } else if error != nil {
            handleError(error)
            textView!.lnv_textDidChange(Notification.init(name: NSNotification.Name.NSTextDidChange, object: nil))
            return false
        } else {
            genericJSONError()
        }
        return false
    }

    /**
   Actual function that generates the model.
   */
    func generateModel(at path: String? = nil, destinationPath: String) -> [String] {
        var generatedFiles = [String]()
        var currentProcessingFilePathUrl: URL!
        // The base class field is blank, cannot proceed without it.
        // Possibly can have a default value in the future.
        if baseClassTextField?.stringValue.count <= 0 {
            let alert = NSAlert()
            alert.messageText = "Enter a base class name to continue."
            alert.runModal()
            return generatedFiles
        }
        
        var object: AnyObject?
        
        if let path = path {
            let url = URL(fileURLWithPath: path)
            guard let jsonData = try? Data(contentsOf: url), let jsonString = String(data: jsonData, encoding: .utf8) else {
                return generatedFiles
            }
            currentProcessingFilePathUrl = url
            object = JSONHelper.convertToObject(jsonString).1
        } else {
            object = JSONHelper.convertToObject(textView?.string).1
        }
    
        let filePath = destinationPath

        // Checks for validity of the content, else can cause crashes.
        if object != nil {

            let jsonObject = JSON(object!)
            
            let jsonType = JsonType(rawValue: jsonTypeSelectorSegment.selectedSegment)!
            let baseClassName = (jsonType == .json) ? authorNameTextField.stringValue : (jsonObject["title"].string ?? "")
            
            
            let nsCodingState = self.enableNSCodingSupportCheckbox.state == 1 && (modelTypeSelectorSegment.selectedSegment == 1)
            let isFinalClass = self.setAsFinalCheckbox.state == 1 && (modelTypeSelectorSegment.selectedSegment == 1)
            let constructType = self.modelTypeSelectorSegment.selectedSegment == 0 ? ConstructType.StructType : ConstructType.ClassType
            let libraryType = libraryForIndex(self.librarySelector.indexOfSelectedItem)
            let configuration = ModelGenerationConfiguration.init(
                                                                filePath: filePath.appending("/"),
                                                                  baseClassName: baseClassName,
                                                                  authorName: authorNameTextField.stringValue,
                                                                  companyName: companyNameTextField.stringValue,
                                                                  prefix: prefixClassTextField.stringValue,
                                                                  constructType: constructType,
                                                                  modelMappingLibrary: libraryType,
                                                                  supportNSCoding: nsCodingState,
                                                                  isFinalRequired: isFinalClass,
                                                                  isHeaderIncluded: includeHeaderImportCheckbox.state == 1 ? true : false,
                                                                  jsonType: JsonType(rawValue: jsonTypeSelectorSegment.selectedSegment)!,
                                                                  jsonFileURL: currentProcessingFilePathUrl)
            var modelGenerator = ModelGenerator.init(jsonObject, configuration)
            let filesGenerated = modelGenerator.generate()
            for file in filesGenerated {
                let content = FileGenerator.generateFileContentWith(file, configuration: configuration)
                let name = file.fileName
                let path = configuration.filePath
                do {
                    try FileGenerator.writeToFileWith(name, content: content, path: path)
                    generatedFiles.append(name)
                } catch let error as NSError {
                    let alert: NSAlert = NSAlert()
                    alert.messageText = "Unable to generate the files, please check the contents of the folder."
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        
            let files = filesGenerated.map({ (file) -> String in
                let filename = "\(file.fileName).swift"
                return filename
            })
            FileGenerator.indent(files: files, at: configuration.filePath)
        } else {
            let alert: NSAlert = NSAlert()
            alert.messageText = "Unable to save the file check the content."
            alert.runModal()
        }
        return generatedFiles
    }

    func libraryForIndex(_ index: Int) -> JSONMappingLibrary {
        if index == 2 {
            return JSONMappingLibrary.ObjectMapper
        } else if index == 3 {
            return JSONMappingLibrary.Marshal
        }
        return JSONMappingLibrary.SwiftyJSON
    }

    @IBAction func recalcEnabledBoxes(_ sender: AnyObject) {
        self.enableNSCodingSupportCheckbox.isEnabled = (modelTypeSelectorSegment.selectedSegment == 1)
        self.setAsFinalCheckbox.isEnabled = (modelTypeSelectorSegment.selectedSegment == 1)
    }
    
    @IBAction func uploadJSONFile(_ sender: NSButton) {
        let openPannel = NSOpenPanel()
        openPannel.begin { (result) in
            if (result == NSFileHandlingPanelOKButton) {
                if let url = openPannel.urls.first {
                    guard let jsonData = try? Data(contentsOf: url), let jsonString = String(data: jsonData, encoding: .utf8) else {
                            return
                    }
                    FileGenerator.executeGitCommand(command: "git pull", at: url.deletingLastPathComponent())
                    self.jsonFilePath = url
                    self.textView.string = jsonString
                }
                // Open  the document.
            }
        }
    }

    func notify(fileCount: Int) {
        let notification = NSUserNotification()
        notification.title = "SwiftyJSONAccelerator"
        if fileCount > 0 {
            notification.subtitle = "Completed - \(fileCount) Files Generated"
        } else {
            notification.subtitle = "No files were generated."
        }
        NSUserNotificationCenter.default.deliver(notification)
    }

    // MARK: Internal Methods

    /**
   Get the line number, column and the character for the position in the given string.

   - parameters:
   - string: The JSON string that is in the textview.
   - position: the location where the error is.

   - returns:
   - character: the string that was causing the issue.
   - line: the linenumber where the error was.
   - column: the column where the error was.
   */
    func characterRowAndLineAt(_ string: String, position: Int)
        -> (character: String, line: Int, column: Int) {
            var lineNumber = 0
            var characterPosition = 0
            for line in string.components(separatedBy: "\n") {
                lineNumber += 1
                var columnNumber = 0
                for column in line.characters {
                    characterPosition += 1
                    columnNumber += 1
                    if characterPosition == position {
                        return (String(column), lineNumber, columnNumber)
                    }
                }
                characterPosition += 1
                if characterPosition == position {
                    return ("\n", lineNumber, columnNumber + 1)
                }
            }
            return ("", 0, 0)
    }

    /**
   Handle Error message that is provided by the JSON helper and extract the message and showing them accordingly.

   - parameters:
   - error: NSError that was provided.
   */
    func handleError(_ error: NSError?) {
        if let message = error!.userInfo["debugDescription"] as? String {
            let numbers = message.components(separatedBy: CharacterSet.decimalDigits.inverted)

            var validNumbers: [Int] = []
            for number in numbers where (Int(number) != nil) {
                validNumbers.append(Int(number)!)
            }

            if validNumbers.count == 1 {
                let index = validNumbers[0]
                let errorPosition: (character: String, line: Int, column: Int) = characterRowAndLineAt((textView?.string)!, position: index)
                let customErrorMessage = "Error at line number: \(errorPosition.line) column: \(errorPosition.column) at Character: \(errorPosition.character)."
                invalidJSONError(customErrorMessage)
            } else {
                invalidJSONError(message)
            }
        } else {
            genericJSONError()
        }
    }

    /**
     Shows a generic error about JSON in case the system is not able to figure out what is wrong.
     */
    func genericJSONError() {
        invalidJSONError("The JSON seems to be invalid!")
    }

    /// MARK: Resetting and showing error messages

    /**
   Reset the whole error view with no image and message.
   */
    func resetErrorImage() {
        errorImageView?.image = nil
        messageLabel?.stringValue = ""
    }

    /**
   Show that the JSON is fine with proper icon.
   */
    func correctJSONMessage() {
        errorImageView?.image = NSImage.init(named: "success")
        messageLabel?.stringValue = "Valid JSON!"
    }

    /**
   Show the invalid JSON error with proper error and message.

   - parameters:
   - message: Error message that is to be shown.
   */
    func invalidJSONError(_ message: String) {
        errorImageView?.image = NSImage.init(named: "failure")
        messageLabel?.stringValue = message
    }

    // MARK: TextView Delegate
    func textDidChange(_ notification: Notification) {
        let isValid = validateAndFormat(false)
        if isValid {
            resetErrorImage()
        }
    }

    @IBAction func librarySwitched(sender: Any) {
        if let menu = sender as? NSPopUpButton {
            self.librarySelector.title = menu.selectedItem!.title
        }
    }

    // MARK: Internal Methods

    /**
   Open the file selector to select a location to save the generated files.

   - returns: Return a valid path or nil.
   */
    func openFile() -> URL? {
        let fileDialog = NSOpenPanel()
        fileDialog.canChooseFiles = true
        fileDialog.canChooseDirectories = true
        fileDialog.canCreateDirectories = true
        if fileDialog.runModal() == NSModalResponseOK {
            return fileDialog.url
        }
        return nil
    }

}
